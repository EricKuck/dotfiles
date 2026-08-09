// One-shot control-socket client used by the aibox CLI: connect, send a single
// line, print the reply. Exit 3 means the socket isn't accepting connections
// (no live broker), which the CLI reads as "session stopped".

use std::io::{Read, Write};
use std::net::Shutdown;
use std::os::unix::net::UnixStream;

pub fn run(args: &[String]) -> i32 {
    let sock = match args.first() {
        Some(s) => s,
        None => {
            eprintln!("usage: aibox-host ctl <sock> <control-secret> <message>");
            return 2;
        }
    };
    let secret = match args.get(1) {
        Some(s) if !s.is_empty() => s,
        _ => {
            eprintln!("aibox ctl: missing control secret");
            return 2;
        }
    };
    let msg = args.get(2).cloned().unwrap_or_default();
    let mut st = match UnixStream::connect(sock) {
        Ok(s) => s,
        Err(_) => return 3,
    };
    let _ = st.write_all(format!("AUTH {secret} {msg}\n").as_bytes());
    let _ = st.shutdown(Shutdown::Write);
    let mut out = String::new();
    let _ = st.read_to_string(&mut out);
    print!("{out}");
    0
}
