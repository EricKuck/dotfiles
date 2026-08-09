// Runs OUTSIDE the sandbox and owns the session. It issues extension tokens,
// launches the sandboxed side via `sandbox-exec ... aibox launch`, forwards
// grants over the socketpair, and serves ALLOW/DENY/LIST from the CLI on a unix
// control socket. When the session exits, so does the broker.

use crate::ffi;
use crate::proto::{read_line, write_all};
use crate::sandbox::Sandbox;
use crate::sqlite::{Database, DenialRow};
use std::fs::{File, OpenOptions};
use std::io::{BufRead, BufReader, Read};
use std::os::unix::fs::PermissionsExt;
use std::os::unix::io::AsRawFd;
use std::os::unix::net::{UnixListener, UnixStream};
use std::path::{Path, PathBuf};
use std::process::{Child, Command, Stdio};
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::{Arc, Mutex};
use std::thread::{self, JoinHandle};
use std::time::Duration;

pub fn run(args: &[String]) -> i32 {
    // aibox broker <control.sock> <profile.sb> <manifest> <control-secret> -- <harness...>
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

    let sb = Sandbox::load();

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
    let mut denial_logger = match start_denial_logger(&denial_log_path()) {
        Ok(logger) => logger,
        Err(e) => {
            eprintln!("aibox broker: denial logger: {e}");
            return 1;
        }
    };

    let mut session: Child = match Command::new("/usr/bin/sandbox-exec")
        .arg("-f")
        .arg(profile)
        .arg(&self_exe)
        .arg("launch")
        .arg("--")
        .args(harness)
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

// One audit database for every workspace and session, so denials can be
// reviewed in one place instead of per-session files that disappear with
// `aibox rm`. Rows are aggregated per (process, operation, pattern, hour), so
// a noisy build collapses into counting rows instead of one line per event.
const DEFAULT_DENIAL_LOG: &str = ".aibox/state/denials.db";
// Keep the newest 30 days of hourly buckets; older aggregated rows are deleted
// on a schedule (the jsonl it replaces rotated at 32 MiB).
const DENIAL_HOURS_KEPT: i64 = 24 * 30;
// Events arrive in bursts (a build's worth of denials in seconds); batch them
// into one transaction per DENIAL_BATCH so each burst costs one fsync, and
// trim the hour window on a looser schedule.
const DENIAL_BATCH: u32 = 64;
const DENIAL_TRIM_EVERY: u32 = 4096;
const ELECTION_INTERVAL: Duration = Duration::from_secs(2);

struct DenialLogger {
    stop: Arc<AtomicBool>,
    stream: Arc<Mutex<Option<Child>>>,
    supervisor: Option<JoinHandle<()>>,
}

impl DenialLogger {
    fn stop(&mut self) {
        self.stop.store(true, Ordering::SeqCst);
        if let Some(child) = self.stream.lock().unwrap().as_mut() {
            let _ = child.kill();
        }
        if let Some(supervisor) = self.supervisor.take() {
            let _ = supervisor.join();
        }
    }
}

fn denial_log_path() -> PathBuf {
    match std::env::var("AIBOX_DENIAL_LOG") {
        Ok(path) if !path.is_empty() => PathBuf::from(path),
        _ => Path::new(&std::env::var("HOME").unwrap_or_default()).join(DEFAULT_DENIAL_LOG),
    }
}

// Seatbelt's `(debug deny)` emits violations to the unified log, which is
// machine-wide: every broker's stream sees every sandbox's denials, and the
// events carry no session identity to filter on. So brokers elect exactly one
// writer through an exclusive lock next to the shared database; the rest idle
// and retry, taking over within ELECTION_INTERVAL if the owning session exits
// first. Rows can still include unrelated system denials.
fn start_denial_logger(path: &Path) -> Result<DenialLogger, String> {
    if let Some(parent) = path.parent() {
        if !parent.exists() {
            std::fs::create_dir_all(parent)
                .map_err(|e| format!("create {}: {e}", parent.display()))?;
            std::fs::set_permissions(parent, std::fs::Permissions::from_mode(0o700))
                .map_err(|e| format!("secure {}: {e}", parent.display()))?;
        }
    }
    // Held for the lifetime of the stream, so it must be a file the writer
    // never rotates out from under the lock.
    let lock_path = path.with_extension("lock");
    let lock = OpenOptions::new()
        .create(true)
        .write(true)
        .truncate(false)
        .open(&lock_path)
        .map_err(|e| format!("open {}: {e}", lock_path.display()))?;
    std::fs::set_permissions(&lock_path, std::fs::Permissions::from_mode(0o600))
        .map_err(|e| format!("secure {}: {e}", lock_path.display()))?;
    // Database initialization and legacy migration intentionally happen only
    // after this broker wins the writer election. A transient SQLite lock or a
    // malformed audit database must not prevent unrelated sandbox sessions
    // from starting.

    let stop = Arc::new(AtomicBool::new(false));
    let stream = Arc::new(Mutex::new(None));
    let supervisor = {
        let (path, stop, stream) = (path.to_path_buf(), Arc::clone(&stop), Arc::clone(&stream));
        thread::spawn(move || supervise_denials(&path, lock, &stop, &stream))
    };
    Ok(DenialLogger {
        stop,
        stream,
        supervisor: Some(supervisor),
    })
}

fn supervise_denials(path: &Path, lock: File, stop: &AtomicBool, stream: &Mutex<Option<Child>>) {
    while !stop.load(Ordering::SeqCst) {
        if !claim(&lock) {
            nap(stop, ELECTION_INTERVAL);
            continue;
        }
        if let Err(e) = stream_denials(path, stop, stream) {
            eprintln!("aibox broker: denial logger: {e}");
        }
        release(&lock);
        // `log stream` dying instantly must not turn the election into a spin.
        nap(stop, ELECTION_INTERVAL);
    }
}

fn claim(lock: &File) -> bool {
    unsafe { ffi::flock(lock.as_raw_fd(), ffi::LOCK_EX | ffi::LOCK_NB) == 0 }
}

fn release(lock: &File) {
    unsafe {
        ffi::flock(lock.as_raw_fd(), ffi::LOCK_UN);
    }
}

fn stream_denials(
    path: &Path,
    stop: &AtomicBool,
    slot: &Mutex<Option<Child>>,
) -> Result<(), String> {
    prepare_legacy_override(path)?;
    let mut db = Database::open(path)?;
    migrate_legacy_jsonl(&mut db, path)?;
    let mut process = Command::new("/usr/bin/log")
        .args([
            "stream",
            "--style",
            "compact",
            "--predicate",
            "eventMessage CONTAINS \"deny(\"",
        ])
        .stdout(Stdio::piped())
        .stderr(Stdio::null())
        .spawn()
        .map_err(|e| format!("start /usr/bin/log: {e}"))?;
    let stdout = process
        .stdout
        .take()
        .ok_or_else(|| "capture /usr/bin/log output".to_string())?;
    *slot.lock().unwrap() = Some(process);
    // Covers a stop that landed before the child was visible to DenialLogger.
    if !stop.load(Ordering::SeqCst) {
        let mut batch = 0u32;
        let mut since_trim = 0u32;
        let mut in_tx = false;
        for line in BufReader::new(stdout).lines().map_while(Result::ok) {
            if stop.load(Ordering::SeqCst) {
                break;
            }
            let Some(d) = parse_denial(&line) else {
                continue;
            };
            if foreign(&d) {
                continue;
            }
            if !in_tx {
                match db.begin() {
                    Ok(()) => in_tx = true,
                    Err(e) => {
                        eprintln!("aibox broker: denial logger: begin: {e}");
                        continue;
                    }
                }
            }
            let row = DenialRow {
                process: &d.process,
                operation: &d.operation,
                pattern: &d.pattern,
                hour: &d.hour,
                timestamp: &d.timestamp,
                pid: i64::from(d.pid),
                count: i64::from(d.count),
                example_path: &d.path,
            };
            if let Err(e) = db.upsert(&row) {
                eprintln!("aibox broker: denial logger: insert: {e}");
                rollback_transaction(&mut db, "insert");
                in_tx = false;
                batch = 0;
                continue;
            }
            batch += 1;
            if batch >= DENIAL_BATCH {
                match db.commit() {
                    Ok(()) => {
                        in_tx = false;
                        batch = 0;
                        since_trim += DENIAL_BATCH;
                        if since_trim >= DENIAL_TRIM_EVERY {
                            since_trim = 0;
                            if let Err(e) = db.trim_old_hours(DENIAL_HOURS_KEPT) {
                                eprintln!("aibox broker: denial logger: trim: {e}");
                            }
                        }
                    }
                    Err(e) => {
                        // SQLite can leave a transaction active after a failed
                        // COMMIT (notably SQLITE_BUSY). Roll it back before the
                        // next line tries BEGIN, otherwise logging wedges.
                        eprintln!("aibox broker: denial logger: commit: {e}");
                        rollback_transaction(&mut db, "commit");
                        in_tx = false;
                        batch = 0;
                    }
                }
            }
        }
        if in_tx {
            if let Err(e) = db.commit() {
                eprintln!("aibox broker: denial logger: commit: {e}");
                rollback_transaction(&mut db, "final commit");
            }
        }
    }
    if let Some(mut process) = slot.lock().unwrap().take() {
        let _ = process.kill();
        let _ = process.wait();
    }
    Ok(())
}

// Import a legacy denials.jsonl (and its rotated .1 generation, if any) into
// the aggregated database. Every source file is one transaction together with
// a durable migration marker: a crash after COMMIT but before rename is safe,
// because the next elected writer sees the marker, only performs the pending
// rename, and never increments the aggregate again. Malformed JSON lines are
// intentionally skipped; any filesystem or SQLite error aborts without
// marking or renaming the source.
fn migrate_legacy_jsonl(db: &mut Database, db_path: &Path) -> Result<(), String> {
    let legacy = db_path.with_extension("jsonl");
    let mut rotated = legacy.as_os_str().to_os_string();
    rotated.push(".1");
    let rotated = PathBuf::from(rotated);
    let mut candidates = Vec::new();
    // Normal case: db at <name>.db, legacy generations at <name>.jsonl[.1].
    if legacy != db_path {
        if rotated.exists() {
            candidates.push(rotated);
        }
        if legacy.exists() {
            candidates.push(legacy);
        }
    }
    // Stale-override case: a jsonl-named path was set aside as <path>.legacy.
    let mut stale = db_path.as_os_str().to_os_string();
    stale.push(".legacy");
    let stale = PathBuf::from(stale);
    if stale.exists() {
        candidates.push(stale);
    }

    for file in candidates {
        let source = file.to_string_lossy().into_owned();
        if db.migration_complete(&source)? {
            rename_migrated(&file)?;
            continue;
        }

        let f = File::open(&file).map_err(|e| format!("open legacy {}: {e}", file.display()))?;
        db.begin()?;
        let imported = (|| -> Result<(), String> {
            for line in BufReader::new(f).lines() {
                let line = line.map_err(|e| format!("read legacy {}: {e}", file.display()))?;
                let Some(record) = legacy_record(&line) else {
                    continue;
                };
                let row = DenialRow {
                    process: &record.process,
                    operation: &record.operation,
                    pattern: &record.pattern,
                    hour: &record.hour,
                    timestamp: &record.timestamp,
                    pid: i64::from(record.pid),
                    count: i64::from(record.count),
                    example_path: &record.path,
                };
                db.upsert(&row)?;
            }
            db.mark_migration_complete(&source)?;
            db.commit()
        })();
        if let Err(e) = imported {
            rollback_transaction(db, "legacy migration");
            return Err(e);
        }
        rename_migrated(&file)?;
    }
    Ok(())
}

fn prepare_legacy_override(path: &Path) -> Result<(), String> {
    if path.extension().is_none_or(|e| e != "jsonl") || !legacy_jsonl_at(path) {
        return Ok(());
    }
    let mut aside = path.as_os_str().to_os_string();
    aside.push(".legacy");
    let aside = PathBuf::from(aside);
    if aside.exists() {
        return Err(format!(
            "refusing to overwrite staged legacy {}",
            aside.display()
        ));
    }
    std::fs::rename(path, &aside).map_err(|e| format!("set aside legacy {}: {e}", path.display()))
}

fn rename_migrated(file: &Path) -> Result<(), String> {
    let mut renamed = file.as_os_str().to_os_string();
    renamed.push(".migrated");
    let renamed = PathBuf::from(renamed);
    if renamed.exists() {
        return Err(format!("refusing to overwrite {}", renamed.display()));
    }
    std::fs::rename(file, &renamed).map_err(|e| format!("rename legacy {}: {e}", file.display()))
}

fn rollback_transaction(db: &mut Database, phase: &str) {
    if let Err(e) = db.rollback() {
        eprintln!("aibox broker: denial logger: rollback after {phase}: {e}");
    }
}

fn nap(stop: &AtomicBool, total: Duration) {
    let slice = Duration::from_millis(250);
    let mut left = total;
    while !left.is_zero() && !stop.load(Ordering::SeqCst) {
        let step = slice.min(left);
        thread::sleep(step);
        left -= step;
    }
}

struct Denial {
    process: String,
    pid: u32,
    operation: String,
    // The original path (kept as the row's example_path) and the normalized
    // pattern that groups it with its noisy siblings.
    path: String,
    pattern: String,
    timestamp: String,
    hour: String,
    // How many events this line stands for: the log coalesces a repeat into
    // "N duplicate reports for ..." rather than emitting it N times.
    count: u32,
}

// macOS platform daemons, which run in their own App Sandboxes and deny against
// their own profiles all day long. They are never part of an aibox session, so
// their events are pure noise in the machine-wide log the broker reads.
// `profile::would_allow` already drops most of what they produce; these are the
// ones whose denials happen to fall outside the profile's static allows. Names
// beginning "com.apple." are covered by the prefix test in `foreign`, so only
// the bare ones are listed. Purely cosmetic: nothing here affects the sandbox.
const SYSTEM_DAEMONS: &[&str] = &[
    "BackgroundShortcutRunner",
    "ScreenTimeAgent",
    "WallpaperAerialsExtension",
    "WeatherWidget",
    "biomesyncd",
    "businessservicesd",
    "deleted",
    "duetexpertd",
    "ecosystemanalyticsd",
    "ecosystemd",
    "findmybeaconingd",
    "findmydeviced",
    "imagent",
    "liveactivitiesd",
    "locationd",
    "logd",
    "logd_helper",
    "managedcorespotlightd",
    "nsattributedstringagent",
    "parsec-fbf",
    "parsecd",
    "searchpartyd",
    "sharingd",
    "suggestd",
    "swcd",
];

// True when this denial provably belongs to some other sandbox on the machine.
fn foreign(d: &Denial) -> bool {
    crate::profile::would_allow(&d.operation, &d.path)
        || d.process.starts_with("com.apple.")
        || SYSTEM_DAEMONS.contains(&d.process.as_str())
}

// A parseable sandbox denial from a compact `log stream` line, or None.
fn parse_denial(line: &str) -> Option<Denial> {
    let (head, rest) = line.split_once(" deny(")?;
    let (_, operation_and_path) = rest.split_once(") ")?;
    let (operation, path) = operation_and_path.split_once(' ')?;
    let (process, pid) = subject(head);
    let timestamp = compact_timestamp(line);
    let path = path.trim();
    Some(Denial {
        process: process.to_string(),
        pid,
        operation: operation.trim().to_string(),
        path: path.to_string(),
        pattern: normalize_path(path),
        timestamp: timestamp.clone(),
        hour: hour_bucket(&timestamp),
        count: duplicate_count(head),
    })
}

// The multiplier on a coalesced line, whose head reads
// "... (Sandbox) 4 duplicate reports for Sandbox: proc(123)". Uncoalesced lines
// stand for one event.
fn duplicate_count(head: &str) -> u32 {
    let Some((before, _)) = head.split_once(" duplicate report") else {
        return 1;
    };
    before
        .rsplit(' ')
        .next()
        .and_then(|n| n.parse().ok())
        .filter(|n| *n > 0)
        .unwrap_or(1)
}

// A legacy jsonl file (as opposed to a sqlite database) starts with '{'.
fn legacy_jsonl_at(path: &Path) -> bool {
    let Ok(mut f) = File::open(path) else {
        return false;
    };
    let mut head = [0u8; 16];
    f.read(&mut head).unwrap_or(0) > 0 && head[0] == b'{'
}

fn compact_timestamp(line: &str) -> String {
    let mut parts = line.split_whitespace();
    match (parts.next(), parts.next()) {
        (Some(date), Some(time)) => format!("{date}T{time}"),
        (Some(value), None) => value.to_string(),
        _ => String::new(),
    }
}

// The event's hour bucket, 'YYYY-MM-DDTHH', from the compact timestamp.
fn hour_bucket(timestamp: &str) -> String {
    timestamp.chars().take(13).collect()
}

// The denying process, from the `Sandbox: fish(123)` prefix. A single shared
// database has no per-session owner to attribute an entry to, so this is the
// only honest identity available.
fn subject(head: &str) -> (&str, u32) {
    let subject = match head.rsplit_once("Sandbox: ") {
        Some((_, s)) => s.trim(),
        None => head.split_whitespace().last().unwrap_or("").trim(),
    };
    match subject.rsplit_once('(') {
        Some((process, pid)) => (process, pid.trim_end_matches(')').parse().unwrap_or(0)),
        None => (subject, 0),
    }
}

// One hand-written JSON record from the legacy .jsonl audit log.
fn legacy_record(line: &str) -> Option<Denial> {
    let timestamp = json_string_field(line, "timestamp")?;
    let process = json_string_field(line, "process")?;
    let pid = json_int_field(line, "pid").unwrap_or(0);
    let operation = json_string_field(line, "operation")?;
    let path = json_string_field(line, "path")?;
    Some(Denial {
        process,
        pid,
        operation,
        path: path.clone(),
        pattern: normalize_path(&path),
        timestamp: timestamp.clone(),
        hour: hour_bucket(&timestamp),
        // The legacy jsonl predates coalescing: one record, one event.
        count: 1,
    })
}

// Value of a JSON string field in the legacy records, with backslash escapes
// resolved. Fields appear in a fixed order, so the first occurrence of
// "key":" is the field itself, not a mention inside the raw line.
fn json_string_field(line: &str, key: &str) -> Option<String> {
    let needle = format!("\"{key}\":\"");
    let start = line.find(&needle)? + needle.len();
    let mut chars = line[start..].chars();
    let mut out = String::new();
    while let Some(c) = chars.next() {
        match c {
            '"' => return Some(out),
            '\\' => match chars.next() {
                Some('"') => out.push('"'),
                Some('\\') => out.push('\\'),
                Some('n') => out.push('\n'),
                Some('r') => out.push('\r'),
                Some('t') => out.push('\t'),
                Some('u') => {
                    let hex: String = chars.by_ref().take(4).collect();
                    if let Ok(v) = u32::from_str_radix(&hex, 16) {
                        out.push(char::from_u32(v).unwrap_or('\u{FFFD}'));
                    }
                }
                _ => return None,
            },
            c => out.push(c),
        }
    }
    None
}

fn json_int_field(line: &str, key: &str) -> Option<u32> {
    let needle = format!("\"{key}\":");
    let start = line.find(&needle)? + needle.len();
    let digits: String = line[start..]
        .chars()
        .take_while(|c| c.is_ascii_digit())
        .collect();
    digits.parse().ok()
}

// Collapses the variable parts of a path so the same failure groups into one
// row: runs of 8+ hex characters become <hash> (cache keys, git object ids,
// build hashes -- checked as one run so a hash that happens to start with a
// digit still collapses), and other runs of digits become \d+ (versions,
// ports, numeric ids).
fn normalize_path(path: &str) -> String {
    let chars: Vec<char> = path.chars().collect();
    let mut out = String::with_capacity(path.len());
    let mut i = 0;
    while i < chars.len() {
        let c = chars[i];
        if c.is_ascii_hexdigit() {
            let start = i;
            while i < chars.len() && chars[i].is_ascii_hexdigit() {
                i += 1;
            }
            if i - start >= 8 {
                out.push_str("<hash>");
            } else if chars[start].is_ascii_digit() {
                // Short run starting with digits: collapse the numeric prefix,
                // keep any trailing hex letters (e.g. cache key "12abc").
                out.push_str("\\d+");
                let mut j = start;
                while j < i && chars[j].is_ascii_digit() {
                    j += 1;
                }
                out.extend(chars[j..i].iter());
            } else {
                out.extend(chars[start..i].iter());
            }
        } else {
            out.push(c);
            i += 1;
        }
    }
    out
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
        match deny(broker_fd, dir) {
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
    let token = sb
        .issue(&real_s)
        .ok_or_else(|| format!("issue failed for {real_s}"))?;
    write_all(broker_fd, &format!("CONSUME {token} {real_s}\n"))
        .map_err(|_| "launcher gone".to_string())?;
    match read_line(broker_fd) {
        Ok(Some(reply)) if reply.starts_with("OK") => Ok(real_s),
        Ok(Some(reply)) => Err(reply),
        _ => Err("launcher gone".to_string()),
    }
}

fn deny(broker_fd: i32, dir: &str) -> Result<String, String> {
    let real = std::fs::canonicalize(dir)
        .map(|p| p.to_string_lossy().into_owned())
        .unwrap_or_else(|_| dir.to_string());
    write_all(broker_fd, &format!("RELEASE {real}\n")).map_err(|_| "launcher gone".to_string())?;
    match read_line(broker_fd) {
        Ok(Some(reply)) if reply.starts_with("OK") => Ok(real),
        Ok(Some(reply)) => Err(reply),
        _ => Err("launcher gone".to_string()),
    }
}

#[cfg(test)]
mod tests {
    use super::{
        claim, foreign, json_string_field, legacy_record, migrate_legacy_jsonl, normalize_path,
        parse_denial, release,
    };
    use crate::sqlite::{Database, DenialRow};
    use std::fs::OpenOptions;

    #[test]
    fn parses_a_compact_sandbox_denial() {
        let line = "2026-03-08 12:34:56.789 Df sandboxd[321:9ab] Sandbox: fish(123) deny(1) file-read-data /Users/eric/.rustup/credentials.toml";
        let d = parse_denial(line).expect("record");
        assert_eq!(d.process, "fish");
        assert_eq!(d.pid, 123);
        assert_eq!(d.operation, "file-read-data");
        assert_eq!(d.path, "/Users/eric/.rustup/credentials.toml");
        assert_eq!(d.timestamp, "2026-03-08T12:34:56.789");
        assert_eq!(d.hour, "2026-03-08T12");
        assert_eq!(d.pattern, "/Users/eric/.rustup/credentials.toml");
        assert_eq!(d.count, 1);
    }

    // The log coalesces a repeat rather than emitting it again, so a line can
    // stand for many events.
    #[test]
    fn counts_coalesced_duplicate_reports() {
        let line = "2026-03-08 12:34:56.789 E  kernel[0:1abc] (Sandbox) 4 duplicate reports for Sandbox: fish(123) deny(1) file-read-data /Users/eric/.netrc";
        let d = parse_denial(line).expect("record");
        assert_eq!(d.process, "fish");
        assert_eq!(d.pid, 123);
        assert_eq!(d.count, 4);
    }

    #[test]
    fn drops_denials_from_other_sandboxes() {
        let foreign_lines = [
            // An operation the profile allows outright.
            "2026-03-08 12:34:56.789 E  kernel[0:1] (Sandbox) Sandbox: ecosystemd(1) deny(1) mach-lookup com.apple.bird",
            // A read under a path the profile allows.
            "2026-03-08 12:34:56.789 E  kernel[0:1] (Sandbox) Sandbox: ScreenTimeAgent(2) deny(1) file-read-data /private/var/db/os_eligibility/eligibility.plist",
            // Neither, but a known platform daemon.
            "2026-03-08 12:34:56.789 E  kernel[0:1] (Sandbox) Sandbox: duetexpertd(3) deny(1) file-read-xattr /Users/eric/Desktop",
            // Reverse-DNS daemon names are covered by prefix.
            "2026-03-08 12:34:56.789 E  kernel[0:1] (Sandbox) Sandbox: com.apple.WebKit.WebContent(4) deny(1) syscall-unix 97",
        ];
        for line in foreign_lines {
            assert!(foreign(&parse_denial(line).expect("record")), "{line}");
        }

        // Ours, and the reason the log exists: `security` is /usr/bin/security
        // running INSIDE the sandbox, not a system daemon.
        let ours = [
            "2026-03-08 12:34:56.789 E  kernel[0:1] (Sandbox) Sandbox: security(5) deny(1) file-read-metadata /Users/eric/Library/Keychains",
            "2026-03-08 12:34:56.789 E  kernel[0:1] (Sandbox) Sandbox: node(6) deny(1) file-read-data /Users/eric/.npmrc",
            "2026-03-08 12:34:56.789 E  kernel[0:1] (Sandbox) Sandbox: zsh(7) deny(1) file-read-data /Users/eric/.zshenv",
        ];
        for line in ours {
            assert!(!foreign(&parse_denial(line).expect("record")), "{line}");
        }
    }

    #[test]
    fn skips_lines_that_are_not_denials() {
        assert!(parse_denial("2026-03-08 12:34:56.789 something else entirely").is_none());
    }

    #[test]
    fn normalizes_noisy_path_components() {
        assert_eq!(
            normalize_path("/Users/eric/.gradle/caches/8.10.2/transforms/0123456789abcdef/foo"),
            "/Users/eric/.gradle/caches/\\d+.\\d+.\\d+/transforms/<hash>/foo"
        );
        // Stable components are left alone.
        assert_eq!(
            normalize_path("/Users/eric/.ssh/config"),
            "/Users/eric/.ssh/config"
        );
    }

    #[test]
    fn reads_legacy_json_records() {
        let line = "{\"timestamp\":\"2026-03-08T12:34:56.789\",\"process\":\"fish\",\"pid\":123,\"operation\":\"file-read-data\",\"path\":\"/tmp/x/8/abc\",\"raw\":\"ignored\"}";
        let d = legacy_record(line).expect("record");
        assert_eq!(d.process, "fish");
        assert_eq!(d.pid, 123);
        assert_eq!(d.path, "/tmp/x/8/abc");
        assert_eq!(d.pattern, "/tmp/x/\\d+/abc");
        assert_eq!(d.hour, "2026-03-08T12");
    }

    #[test]
    fn json_string_field_unescapes() {
        assert_eq!(
            json_string_field(r#"{"path":"a\"b\\c"}"#, "path").as_deref(),
            Some("a\"b\\c")
        );
    }

    #[test]
    fn migrates_legacy_jsonl() {
        use crate::sqlite::Database;
        use std::io::Write;

        let dir = std::env::temp_dir().join(format!("aibox-migrate-{}", std::process::id()));
        let _ = std::fs::remove_dir_all(&dir);
        std::fs::create_dir_all(&dir).unwrap();
        let db_path = dir.join("denials.db");
        // Legacy current generation plus the rotated .1 generation.
        let legacy = dir.join("denials.jsonl");
        let rotated = dir.join("denials.jsonl.1");
        let mut f = std::fs::File::create(&rotated).unwrap();
        writeln!(f, "{{\"timestamp\":\"2026-03-08T10:00:00.000\",\"process\":\"fish\",\"pid\":1,\"operation\":\"op\",\"path\":\"/a/1/x\"}}").unwrap();
        drop(f);
        let mut f = std::fs::File::create(&legacy).unwrap();
        writeln!(f, "{{\"timestamp\":\"2026-03-08T12:00:00.000\",\"process\":\"fish\",\"pid\":2,\"operation\":\"op\",\"path\":\"/a/2/x\"}}").unwrap();
        writeln!(f, "{{\"timestamp\":\"2026-03-08T12:30:00.000\",\"process\":\"fish\",\"pid\":3,\"operation\":\"op\",\"path\":\"/a/3/x\"}}").unwrap();
        drop(f);
        // A stale jsonl-named override was set aside as <db>.legacy; it must
        // be imported too.
        let mut f = std::fs::File::create(dir.join("denials.db.legacy")).unwrap();
        writeln!(f, "{{\"timestamp\":\"2026-03-08T14:00:00.000\",\"process\":\"fish\",\"pid\":4,\"operation\":\"op\",\"path\":\"/a/4/x\"}}").unwrap();
        drop(f);

        let mut db = Database::open(&db_path).unwrap();
        super::migrate_legacy_jsonl(&mut db, &db_path).unwrap();
        // Both generations plus the stale override imported (4 events), one
        // row per hour (three hours -> three rows).
        let row = db
            .query_row("SELECT COUNT(*), SUM(count), MIN(pattern) FROM denials")
            .unwrap();
        assert_eq!(row, ["3", "4", "/a/\\d+/x"]);
        assert!(!legacy.exists());
        assert!(dir.join("denials.jsonl.migrated").exists());
        assert!(dir.join("denials.jsonl.1.migrated").exists());
        assert!(dir.join("denials.db.legacy.migrated").exists());
        drop(db);
        let _ = std::fs::remove_dir_all(&dir);
    }

    // Only one broker may stream into the shared database; the rest must lose
    // the election and be able to win it once the owner is gone.
    #[test]
    fn migration_marker_prevents_reimport_after_rename_crash() {
        use std::io::Write;

        let dir =
            std::env::temp_dir().join(format!("aibox-migration-marker-{}", std::process::id()));
        let _ = std::fs::remove_dir_all(&dir);
        std::fs::create_dir_all(&dir).unwrap();
        let db_path = dir.join("denials.db");
        let legacy = dir.join("denials.jsonl");
        let mut f = std::fs::File::create(&legacy).unwrap();
        writeln!(f, "{{\"timestamp\":\"2026-03-08T12:00:00.000\",\"process\":\"fish\",\"pid\":2,\"operation\":\"op\",\"path\":\"/a/2/x\"}}").unwrap();
        drop(f);

        let mut db = Database::open(&db_path).unwrap();
        // Simulate a crash after the import transaction committed but before
        // the source file was renamed. The durable marker must make recovery
        // rename-only rather than increment count a second time.
        db.begin().unwrap();
        db.upsert(&DenialRow {
            process: "fish",
            operation: "op",
            pattern: "/a/\\d+/x",
            hour: "2026-03-08T12",
            timestamp: "2026-03-08T12:00:00.000",
            pid: 2,
            count: 1,
            example_path: "/a/2/x",
        })
        .unwrap();
        db.mark_migration_complete(&legacy.to_string_lossy())
            .unwrap();
        db.commit().unwrap();

        migrate_legacy_jsonl(&mut db, &db_path).unwrap();
        assert_eq!(db.query_row("SELECT count FROM denials").unwrap(), ["1"]);
        assert!(!legacy.exists());
        assert!(dir.join("denials.jsonl.migrated").exists());
        drop(db);
        let _ = std::fs::remove_dir_all(&dir);
    }

    #[test]
    fn migration_failure_keeps_source_for_retry() {
        use std::io::Write;

        let dir =
            std::env::temp_dir().join(format!("aibox-migration-retry-{}", std::process::id()));
        let _ = std::fs::remove_dir_all(&dir);
        std::fs::create_dir_all(&dir).unwrap();
        let db_path = dir.join("denials.db");
        let legacy = dir.join("denials.jsonl");
        let mut f = std::fs::File::create(&legacy).unwrap();
        writeln!(f, "{{\"timestamp\":\"2026-03-08T12:00:00.000\",\"process\":\"fish\",\"pid\":2,\"operation\":\"op\",\"path\":\"/a/2/x\"}}").unwrap();
        drop(f);

        let mut db = Database::open(&db_path).unwrap();
        let mut blocker = Database::open(&db_path).unwrap();
        db.exec("PRAGMA busy_timeout=1").unwrap();
        blocker.begin().unwrap();
        assert!(migrate_legacy_jsonl(&mut db, &db_path).is_err());
        assert!(legacy.exists());
        assert!(!db.migration_complete(&legacy.to_string_lossy()).unwrap());

        blocker.rollback().unwrap();
        migrate_legacy_jsonl(&mut db, &db_path).unwrap();
        assert!(!legacy.exists());
        assert_eq!(db.query_row("SELECT count FROM denials").unwrap(), ["1"]);
        drop(blocker);
        drop(db);
        let _ = std::fs::remove_dir_all(&dir);
    }

    #[test]
    fn elects_a_single_denial_writer() {
        let path = std::env::temp_dir().join(format!("aibox-election-{}.lock", std::process::id()));
        let open = || {
            OpenOptions::new()
                .create(true)
                .write(true)
                .truncate(false)
                .open(&path)
                .expect("open lock")
        };
        let owner = open();
        let contender = open();
        assert!(claim(&owner));
        assert!(!claim(&contender));
        release(&owner);
        assert!(claim(&contender));
        release(&contender);
        let _ = std::fs::remove_file(&path);
    }
}
