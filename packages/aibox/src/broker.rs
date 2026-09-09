// Runs OUTSIDE the sandbox and owns the session. It issues the grants the
// sandboxed side applies, launches that side through the platform's jail
// (`sandbox-exec` on macOS, `bwrap` on Linux), forwards grants over the
// socketpair, and serves ALLOW/DENY/LIST from the CLI on a unix control
// socket. When the session exits, so does the broker.

use crate::denials;
use crate::ffi;
use crate::proto::{b64_encode, read_line, write_all};
use crate::sandbox::Sandbox;
use std::fs::File;
use std::io::{BufRead, BufReader};
use std::os::unix::fs::PermissionsExt;
use std::os::unix::io::AsRawFd;
use std::os::unix::net::{UnixListener, UnixStream};
use std::path::Path;
use std::process::Child;

pub fn run(args: &[String]) -> i32 {
    // aibox broker <control.sock> <policy> <manifest> <control-secret> -- <harness...>
    if args.len() < 5 {
        eprintln!("usage: aibox broker <control.sock> <profile> <manifest> <control-secret> -- <harness...>");
        return 2;
    }
    let control = &args[0];
    let profile = &args[1];
    let manifest = &args[2];
    let control_secret = &args[3];
    if control_secret.is_empty() {
        eprintln!("aibox broker: empty control secret");
        return 2;
    }
    let mut idx = 4;
    if args[idx] == "--" {
        idx += 1;
    }
    if idx >= args.len() {
        eprintln!("aibox broker: no harness command");
        return 2;
    }
    let harness = &args[idx..];

    unsafe {
        ffi::signal(ffi::SIGPIPE, ffi::SIG_IGN);
    }

    // Outside the sandbox, this is what can widen it: on macOS the ability to
    // issue extension tokens, on Linux a private mount namespace whose grant
    // carrier propagates into the session.
    let sb = match Sandbox::host() {
        Ok(sb) => sb,
        Err(e) => {
            eprintln!("aibox broker: {e}");
            return 1;
        }
    };

    let mut sv = [0i32; 2];
    if unsafe { ffi::socketpair(ffi::AF_UNIX, ffi::SOCK_STREAM, 0, sv.as_mut_ptr()) } != 0 {
        eprintln!("aibox broker: socketpair failed");
        return 1;
    }
    let broker_fd = sv[0];
    let child_fd = sv[1];
    // Our end must not leak into the sandboxed child; its end must be inherited.
    ffi::set_cloexec(broker_fd);

    let _ = std::fs::remove_file(control);
    let listener = match UnixListener::bind(control) {
        Ok(l) => l,
        Err(e) => {
            eprintln!("aibox broker: bind {control}: {e}");
            return 1;
        }
    };
    if let Err(e) = std::fs::set_permissions(control, std::fs::Permissions::from_mode(0o600)) {
        eprintln!("aibox broker: secure {control}: {e}");
        return 1;
    }
    listener.set_nonblocking(true).ok();

    let self_exe = std::env::current_exe().expect("current_exe");
    let mut denial_logger = match denials::start() {
        Ok(logger) => logger,
        Err(e) => {
            eprintln!("aibox broker: denial logger: {e}");
            return 1;
        }
    };

    let mut command = match sb.session_command(Path::new(profile), &self_exe, harness) {
        Ok(c) => c,
        Err(e) => {
            denial_logger.stop();
            eprintln!("aibox broker: {e}");
            return 1;
        }
    };
    let mut session: Child = match command
        .env("AIBOX_CHANNEL_FD", child_fd.to_string())
        .spawn()
    {
        Ok(c) => c,
        Err(e) => {
            denial_logger.stop();
            eprintln!("aibox broker: spawn session: {e}");
            return 1;
        }
    };
    // Drop our copy of the inherited end now that the child holds it.
    unsafe {
        ffi::close(child_fd);
    }

    // Re-grant everything the manifest persisted from earlier sessions.
    if let Ok(f) = File::open(manifest) {
        for line in BufReader::new(f).lines().map_while(Result::ok) {
            let d = line.trim();
            if !d.is_empty() {
                let _ = allow(&sb, broker_fd, d);
            }
        }
    }

    let listener_fd = listener.as_raw_fd();
    let mut exit_code = 0;
    loop {
        let mut pfds = [
            ffi::pollfd {
                fd: listener_fd,
                events: ffi::POLLIN,
                revents: 0,
            },
            ffi::pollfd {
                fd: broker_fd,
                events: ffi::POLLIN,
                revents: 0,
            },
        ];
        let r = unsafe { ffi::poll(pfds.as_mut_ptr(), 2, 250) };
        if r > 0 {
            if pfds[0].revents & ffi::POLLIN != 0 {
                if let Ok((conn, _)) = listener.accept() {
                    handle_control(&sb, broker_fd, conn, manifest, control_secret);
                }
            }
            if pfds[1].revents & (ffi::POLLHUP | ffi::POLLERR) != 0 {
                break; // launcher gone
            }
        }
        if let Ok(Some(status)) = session.try_wait() {
            exit_code = status.code().unwrap_or(128);
            break;
        }
    }

    let _ = std::fs::remove_file(control);
    denial_logger.stop();
    exit_code
}



fn handle_control(
    sb: &Sandbox,
    broker_fd: i32,
    conn: UnixStream,
    manifest: &str,
    control_secret: &str,
) {
    let cfd = conn.as_raw_fd();
    let line = match read_line(cfd) {
        Ok(Some(l)) => l,
        _ => return,
    };

    // The control socket is reachable through the profile's broad network rule,
    // even though its parent directory is not file-readable.  A per-session
    // capability therefore distinguishes the host CLI (which reads it from the
    // hard-denied state directory) from the sandboxed harness.
    let Some(rest) = line.strip_prefix("AUTH ") else {
        let _ = write_all(cfd, "ERR unauthorized\n");
        return;
    };
    let Some((provided, request)) = rest.split_once(' ') else {
        let _ = write_all(cfd, "ERR unauthorized\n");
        return;
    };
    if provided != control_secret {
        let _ = write_all(cfd, "ERR unauthorized\n");
        return;
    }

    if let Some(dir) = request.strip_prefix("ALLOW ") {
        match allow(sb, broker_fd, dir) {
            Ok(_) => {
                let _ = write_all(cfd, "OK\n");
            }
            Err(e) => {
                let _ = write_all(cfd, &format!("ERR {e}\n"));
            }
        }
    } else if let Some(dir) = request.strip_prefix("DENY ") {
        match deny(sb, broker_fd, dir) {
            Ok(_) => {
                let _ = write_all(cfd, "OK\n");
            }
            Err(e) => {
                let _ = write_all(cfd, &format!("ERR {e}\n"));
            }
        }
    } else if request == "LIST" {
        if let Ok(f) = File::open(manifest) {
            for l in BufReader::new(f).lines().map_while(Result::ok) {
                let _ = write_all(cfd, &format!("{l}\n"));
            }
        }
    } else {
        let _ = write_all(cfd, "ERR unknown\n");
    }
}

// Issues a token for dir and has the launcher consume it. Returns the resolved
// absolute path on success.
fn allow(sb: &Sandbox, broker_fd: i32, dir: &str) -> Result<String, String> {
    let real = std::fs::canonicalize(dir).map_err(|_| format!("no such directory: {dir}"))?;
    let meta = std::fs::metadata(&real).map_err(|e| e.to_string())?;
    if !meta.is_dir() {
        return Err(format!("not a directory: {}", real.display()));
    }
    let real_s = real.to_string_lossy().into_owned();
    let token = sb.issue(&real_s)?;
    // The token embeds the target path (spaces included); base64 keeps the
    // first-space split in the launcher exact.
    write_all(
        broker_fd,
        &format!("CONSUME {} {real_s}\n", b64_encode(token.as_bytes())),
    )
    .map_err(|_| "launcher gone".to_string())?;
    match read_line(broker_fd) {
        Ok(Some(reply)) if reply.starts_with("OK") => Ok(real_s),
        Ok(Some(reply)) => Err(reply),
        _ => Err("launcher gone".to_string()),
    }
}

fn deny(sb: &Sandbox, broker_fd: i32, dir: &str) -> Result<String, String> {
    let real = std::fs::canonicalize(dir)
        .map(|p| p.to_string_lossy().into_owned())
        .unwrap_or_else(|_| dir.to_string());
    write_all(broker_fd, &format!("RELEASE {real}\n")).map_err(|_| "launcher gone".to_string())?;
    let reply = match read_line(broker_fd) {
        Ok(Some(reply)) => reply,
        _ => return Err("launcher gone".to_string()),
    };
    // The sandboxed side has let go, so whatever the broker itself holds open
    // for this directory can go too.
    sb.revoke(&real);
    if reply.starts_with("OK") {
        Ok(real)
    } else {
        Err(reply)
    }
}

