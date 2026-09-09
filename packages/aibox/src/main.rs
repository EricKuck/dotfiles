// aibox runs an AI coding harness inside a per-workspace filesystem sandbox:
// Seatbelt on macOS, bubblewrap on Linux. The two backends differ in how a
// policy is expressed and in how a running sandbox is widened, so each is a
// module pair behind the same names -- `profile` generates the policy the jail
// is started with, `sandbox` issues and applies live grants.

mod broker;
mod ctl;
mod ffi;
mod launcher;
mod proto;
mod repo;

#[cfg(target_os = "macos")]
mod profile;
#[cfg(target_os = "linux")]
#[path = "plan.rs"]
mod profile;

// The bwrap plan is pure path arithmetic, so it is compiled and tested
// wherever aibox is built rather than only where it runs.
#[cfg(all(test, not(target_os = "linux")))]
#[path = "plan.rs"]
#[allow(dead_code)]
mod plan;

#[cfg(target_os = "macos")]
mod sandbox;
#[cfg(target_os = "linux")]
#[path = "bwrap.rs"]
mod sandbox;

#[cfg(target_os = "macos")]
mod denials;
#[cfg(not(target_os = "macos"))]
#[path = "denials_off.rs"]
mod denials;

#[cfg(target_os = "macos")]
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
