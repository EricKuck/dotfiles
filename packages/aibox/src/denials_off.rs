// Denial auditing has no Linux counterpart. Seatbelt reports every violation
// against a profile to the unified log; a bubblewrap sandbox denies by
// omission -- an unmounted path is simply not there -- so there is no
// violation stream to record. The session still names the same database in
// `aibox status`, and this side of the split keeps the broker free of
// platform conditionals.

pub struct Logger;

impl Logger {
    pub fn stop(&mut self) {}
}

pub fn start() -> Result<Logger, String> {
    Ok(Logger)
}
