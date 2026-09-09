// The sandbox root process. The jail launches this inside the sandbox; it
// applies and releases the grants pushed over the inherited socketpair fd,
// then runs the harness as its child. On macOS a consumed extension applies to
// the shared sandbox label; on Linux the bind lands in the mount namespace the
// harness is forked into. Either way the already-running harness gains
// directories live.

use crate::ffi;
use crate::proto::{b64_decode, read_line, write_all};
use crate::sandbox::Sandbox;
use std::process::Command;

struct Grant {
    dir: String,
    handle: i64,
}

pub fn run(args: &[String]) -> i32 {
    let mut idx = 0;
    if idx < args.len() && args[idx] == "--" {
        idx += 1;
    }
    if idx >= args.len() {
        eprintln!("aibox launch: no harness command");
        return 2;
    }
    let harness = &args[idx..];

    let fd: i32 = match std::env::var("AIBOX_CHANNEL_FD")
        .ok()
        .and_then(|s| s.parse().ok())
    {
        Some(f) => f,
        None => {
            eprintln!("aibox launch: AIBOX_CHANNEL_FD not set");
            return 1;
        }
    };
    // The harness must not inherit the control channel.
    ffi::set_cloexec(fd);

    let sb = match Sandbox::guest() {
        Ok(sb) => sb,
        Err(e) => {
            eprintln!("aibox launch: {e}");
            return 1;
        }
    };

    // The harness must inherit whatever the guest set up, so it is spawned
    // only once that is in place.
    let mut command = Command::new(&harness[0]);
    command.args(&harness[1..]);
    hide_agent_sockets(&mut command);
    let mut child = match command.spawn() {
        Ok(c) => c,
        Err(e) => {
            eprintln!("aibox launch: spawn harness: {e}");
            return 1;
        }
    };

    let mut grants: Vec<Grant> = Vec::new();

    let code = loop {
        let mut pfd = ffi::pollfd {
            fd,
            events: ffi::POLLIN,
            revents: 0,
        };
        let r = unsafe { ffi::poll(&mut pfd, 1, 250) };
        if r > 0 && (pfd.revents & ffi::POLLIN) != 0 {
            match read_line(fd) {
                Ok(Some(line)) => handle_line(&sb, fd, &line, &mut grants),
                _ => break child.wait().ok().and_then(|s| s.code()).unwrap_or(0),
            }
        }
        if let Ok(Some(status)) = child.try_wait() {
            break status.code().unwrap_or(128);
        }
    };

    for g in &grants {
        sb.release(g.handle, &g.dir);
    }
    code
}

// The credential agents are unreachable from inside either sandbox -- Seatbelt
// denies the connect, the mount plan covers the socket -- but a variable that
// still names one turns that into a hang or a puzzling failure deep inside
// whatever tool followed it. Clearing them takes the ordinary "no agent"
// path instead, and stops advertising where the socket was. DOCKER_HOST is
// left alone when it names a TCP endpoint, which is reachable and not a
// credential channel.
fn hide_agent_sockets(command: &mut Command) {
    for name in ["SSH_AUTH_SOCK", "SSH_AGENT_PID", "GPG_AGENT_INFO"] {
        command.env_remove(name);
    }
    if let Ok(host) = std::env::var("DOCKER_HOST") {
        if host.starts_with("unix:") || host.starts_with('/') {
            command.env_remove("DOCKER_HOST");
        }
    }
}

fn handle_line(sb: &Sandbox, fd: i32, line: &str, grants: &mut Vec<Grant>) {
    // "CONSUME <b64-token> <dir...>" -- the token is base64 (it embeds the
    // target path, spaces included, so it may itself contain spaces; the base64
    // form never does), the directory may contain spaces and is taken verbatim.
    if let Some(rest) = line.strip_prefix("CONSUME ") {
        match rest.split_once(' ') {
            Some((token_b64, dir)) => match b64_decode(token_b64).and_then(|t| String::from_utf8(t).ok()) {
                Some(token) => match sb.consume(&token, dir) {
                    Ok(h) => {
                        grants.push(Grant {
                            dir: dir.to_string(),
                            handle: h,
                        });
                        let _ = write_all(fd, &format!("OK {h}\n"));
                    }
                    Err(e) => {
                        let _ = write_all(fd, &format!("ERR consume-failed {e}\n"));
                    }
                },
                None => {
                    let _ = write_all(fd, "ERR malformed\n");
                }
            },
            None => {
                let _ = write_all(fd, "ERR malformed\n");
            }
        }
    } else if let Some(dir) = line.strip_prefix("RELEASE ") {
        match grants.iter().position(|g| g.dir == dir) {
            Some(pos) => {
                sb.release(grants[pos].handle, &grants[pos].dir);
                grants.swap_remove(pos);
                let _ = write_all(fd, "OK\n");
            }
            None => {
                let _ = write_all(fd, "ERR not-held\n");
            }
        }
    } else {
        let _ = write_all(fd, "ERR unknown\n");
    }
}
