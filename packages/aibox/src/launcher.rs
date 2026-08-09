// The sandbox root process. sandbox-exec launches this inside the profile; it
// consumes/releases extension tokens pushed over the inherited socketpair fd,
// then runs the harness as its child. Because consumed extensions apply to the
// shared sandbox label, the already-running harness gains directories live.

use crate::ffi;
use crate::proto::{read_line, write_all};
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

    let sb = Sandbox::load();

    let mut child = match Command::new(&harness[0]).args(&harness[1..]).spawn() {
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
        sb.release(g.handle);
    }
    code
}

fn handle_line(sb: &Sandbox, fd: i32, line: &str, grants: &mut Vec<Grant>) {
    // "CONSUME <token> <dir...>" -- token first because a directory may contain
    // spaces while the token never does.
    if let Some(rest) = line.strip_prefix("CONSUME ") {
        match rest.split_once(' ') {
            Some((token, dir)) => match sb.consume(token) {
                Some(h) => {
                    grants.push(Grant {
                        dir: dir.to_string(),
                        handle: h,
                    });
                    let _ = write_all(fd, &format!("OK {h}\n"));
                }
                None => {
                    let _ = write_all(fd, "ERR consume-failed\n");
                }
            },
            None => {
                let _ = write_all(fd, "ERR malformed\n");
            }
        }
    } else if let Some(dir) = line.strip_prefix("RELEASE ") {
        match grants.iter().position(|g| g.dir == dir) {
            Some(pos) => {
                sb.release(grants[pos].handle);
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
