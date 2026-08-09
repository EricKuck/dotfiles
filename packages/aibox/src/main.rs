mod broker;
mod ctl;
mod ffi;
mod launcher;
mod profile;
mod proto;
mod sandbox;
mod sqlite;

use std::process::exit;

fn main() {
    let args: Vec<String> = std::env::args().collect();
    if args.len() < 2 {
        eprintln!("usage: aibox-host <broker|launch|profile|ctl> ...");
        exit(2);
    }
    let rest = &args[2..];
    match args[1].as_str() {
        "broker" => exit(broker::run(rest)),
        "launch" => exit(launcher::run(rest)),
        "profile" => exit(profile::run(rest)),
        "ctl" => exit(ctl::run(rest)),
        other => {
            eprintln!("aibox: unknown mode {other}");
            exit(2);
        }
    }
}
