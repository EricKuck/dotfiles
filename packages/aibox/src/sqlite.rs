// Minimal runtime binding to the system SQLite (/usr/lib/libsqlite3.dylib),
// dlopened at runtime exactly like the private sandbox-extension functions in
// sandbox.rs, so the crate still carries no dependencies and builds offline.
// Only the slice of the C API the denial logger needs is declared.

use crate::ffi;
use std::ffi::{CStr, CString};
use std::os::raw::{c_char, c_int, c_void};
use std::os::unix::fs::PermissionsExt;
use std::path::Path;

const SQLITE_OK: c_int = 0;
const SQLITE_ROW: c_int = 100;
const SQLITE_DONE: c_int = 101;
const SQLITE_OPEN_READWRITE: c_int = 0x0000_0002;
const SQLITE_OPEN_CREATE: c_int = 0x0000_0004;
// sqlite3_bind_text destructor sentinel: copy the string at bind time so the
// caller's CString can be dropped immediately after.
const SQLITE_TRANSIENT: isize = -1;

type OpenV2Fn =
    unsafe extern "C" fn(*const c_char, *mut *mut c_void, c_int, *const c_char) -> c_int;
type ExecFn = unsafe extern "C" fn(
    *mut c_void,
    *const c_char,
    *mut c_void,
    *mut c_void,
    *mut *mut c_char,
) -> c_int;
type PrepareFn = unsafe extern "C" fn(
    *mut c_void,
    *const c_char,
    c_int,
    *mut *mut c_void,
    *mut *const c_char,
) -> c_int;
type BindTextFn = unsafe extern "C" fn(*mut c_void, c_int, *const c_char, c_int, isize) -> c_int;
type BindInt64Fn = unsafe extern "C" fn(*mut c_void, c_int, i64) -> c_int;
type StepFn = unsafe extern "C" fn(*mut c_void) -> c_int;
type FinalizeFn = unsafe extern "C" fn(*mut c_void) -> c_int;
type CloseFn = unsafe extern "C" fn(*mut c_void) -> c_int;
type ErrmsgFn = unsafe extern "C" fn(*mut c_void) -> *const c_char;
type FreeFn = unsafe extern "C" fn(*mut c_void);
#[cfg(test)]
type ColumnCountFn = unsafe extern "C" fn(*mut c_void) -> c_int;
#[cfg(test)]
type ColumnTextFn = unsafe extern "C" fn(*mut c_void, c_int) -> *const c_char;

// Schema for the shared denial database. One row per (process, operation,
// pattern, hour): path digit runs are normalized to \d+ and long hex runs to
// <hash>, so a noisy build collapses thousands of events into a handful of
// counting rows instead of one line each. first_seen/example_path are set on
// insert and never touched again; count/last_seen/last_pid are bumped by the
// conflict update. denial_migrations makes jsonl import resumable without
// double-counting after a crash between database commit and source rename.
const DDL: &str = "PRAGMA auto_vacuum=INCREMENTAL;\
PRAGMA busy_timeout=2000;\
PRAGMA synchronous=NORMAL;\
CREATE TABLE IF NOT EXISTS denials (\
process TEXT NOT NULL,\
operation TEXT NOT NULL,\
pattern TEXT NOT NULL,\
hour TEXT NOT NULL,\
count INTEGER NOT NULL DEFAULT 1,\
first_seen TEXT NOT NULL,\
last_seen TEXT NOT NULL,\
last_pid INTEGER,\
example_path TEXT,\
PRIMARY KEY (process, operation, pattern, hour));\
CREATE INDEX IF NOT EXISTS idx_denials_hour ON denials(hour);\
CREATE TABLE IF NOT EXISTS denial_migrations (source TEXT PRIMARY KEY);";

pub struct DenialRow<'a> {
    pub process: &'a str,
    pub operation: &'a str,
    pub pattern: &'a str,
    pub hour: &'a str,
    pub timestamp: &'a str,
    pub pid: i64,
    // Events this row stands for, normally 1. The unified log coalesces a
    // repeated denial into a single "N duplicate reports" line.
    pub count: i64,
    pub example_path: &'a str,
}

pub struct Database {
    lib: *mut c_void,
    db: *mut c_void,
    exec: ExecFn,
    prepare: PrepareFn,
    bind_text: BindTextFn,
    bind_int64: BindInt64Fn,
    step: StepFn,
    finalize: FinalizeFn,
    close: CloseFn,
    errmsg: ErrmsgFn,
    free: FreeFn,
    #[cfg(test)]
    column_count: ColumnCountFn,
    #[cfg(test)]
    column_text: ColumnTextFn,
}

impl Database {
    pub fn open(path: &Path) -> Result<Database, String> {
        let c_path = CString::new(path.to_string_lossy().as_bytes())
            .map_err(|_| format!("sqlite path has NUL: {}", path.display()))?;
        let lib = ffi::dlopen(c"/usr/lib/libsqlite3.dylib".as_ptr(), ffi::RTLD_NOW);
        if lib.is_null() {
            return Err("dlopen libsqlite3 failed".to_string());
        }

        // Resolve every symbol before opening the database. This leaves exactly
        // one cleanup path for lookup failures and prevents a partially built
        // Database from leaking an sqlite connection or dylib handle.
        macro_rules! resolve {
            ($name:literal, $ty:ty) => {{
                let name = CString::new($name).expect("SQLite symbol has no NUL");
                let symbol = unsafe { ffi::dlsym(lib, name.as_ptr()) };
                if symbol.is_null() {
                    ffi::dlclose(lib);
                    return Err(format!("dlsym {} failed", $name));
                }
                unsafe { std::mem::transmute::<*mut c_void, $ty>(symbol) }
            }};
        }

        let open_v2: OpenV2Fn = resolve!("sqlite3_open_v2", OpenV2Fn);
        let exec: ExecFn = resolve!("sqlite3_exec", ExecFn);
        let prepare: PrepareFn = resolve!("sqlite3_prepare_v2", PrepareFn);
        let bind_text: BindTextFn = resolve!("sqlite3_bind_text", BindTextFn);
        let bind_int64: BindInt64Fn = resolve!("sqlite3_bind_int64", BindInt64Fn);
        let step: StepFn = resolve!("sqlite3_step", StepFn);
        let finalize: FinalizeFn = resolve!("sqlite3_finalize", FinalizeFn);
        let close: CloseFn = resolve!("sqlite3_close", CloseFn);
        let errmsg: ErrmsgFn = resolve!("sqlite3_errmsg", ErrmsgFn);
        let free: FreeFn = resolve!("sqlite3_free", FreeFn);
        #[cfg(test)]
        let column_count: ColumnCountFn = resolve!("sqlite3_column_count", ColumnCountFn);
        #[cfg(test)]
        let column_text: ColumnTextFn = resolve!("sqlite3_column_text", ColumnTextFn);

        let mut db: *mut c_void = std::ptr::null_mut();
        let rc = unsafe {
            open_v2(
                c_path.as_ptr(),
                &mut db,
                SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE,
                std::ptr::null(),
            )
        };
        if rc != SQLITE_OK || db.is_null() {
            let msg = if db.is_null() {
                "sqlite open failed".to_string()
            } else {
                let text = cstr(unsafe { errmsg(db) });
                unsafe { close(db) };
                text
            };
            ffi::dlclose(lib);
            return Err(format!("sqlite open {}: {msg}", path.display()));
        }

        // An audit record of a user's filesystem shape stays private, like the
        // jsonl it replaces. Clean up explicitly because Database has not yet
        // been constructed if this fails.
        if let Err(e) = std::fs::set_permissions(path, std::fs::Permissions::from_mode(0o600)) {
            unsafe { close(db) };
            ffi::dlclose(lib);
            return Err(format!("secure {}: {e}", path.display()));
        }

        let mut database = Database {
            lib,
            db,
            exec,
            prepare,
            bind_text,
            bind_int64,
            step,
            finalize,
            close,
            errmsg,
            free,
            #[cfg(test)]
            column_count,
            #[cfg(test)]
            column_text,
        };
        database.exec(DDL)?;
        Ok(database)
    }

    pub fn exec(&mut self, sql: &str) -> Result<(), String> {
        let c = CString::new(sql).map_err(|_| "sql contains NUL".to_string())?;
        let mut err: *mut c_char = std::ptr::null_mut();
        let rc = unsafe {
            (self.exec)(
                self.db,
                c.as_ptr(),
                std::ptr::null_mut(),
                std::ptr::null_mut(),
                &mut err,
            )
        };
        if rc != SQLITE_OK {
            let msg = self.err();
            if !err.is_null() {
                unsafe { (self.free)(err.cast()) };
            }
            return Err(msg);
        }
        Ok(())
    }

    // Claim the write lock before buffering a batch. A reader can still make
    // COMMIT busy in rollback-journal mode, so callers must roll back on every
    // error path before beginning another transaction.
    pub fn begin(&mut self) -> Result<(), String> {
        self.exec("BEGIN IMMEDIATE")
    }

    pub fn commit(&mut self) -> Result<(), String> {
        self.exec("COMMIT")
    }

    pub fn rollback(&mut self) -> Result<(), String> {
        self.exec("ROLLBACK")
    }

    // One aggregated row per (process, operation, pattern, hour). The conflict
    // clause bumps count/last_seen/last_pid and leaves first_seen and
    // example_path as the originals from the first sighting.
    pub fn upsert(&mut self, row: &DenialRow<'_>) -> Result<(), String> {
        let sql = "INSERT INTO denials \
            (process, operation, pattern, hour, count, first_seen, last_seen, last_pid, example_path) \
            VALUES (?1, ?2, ?3, ?4, ?8, ?5, ?5, ?6, ?7) \
            ON CONFLICT(process, operation, pattern, hour) DO UPDATE SET \
            count = denials.count + excluded.count, \
            last_seen = excluded.last_seen, \
            last_pid = excluded.last_pid";
        let stmt = self.prepare(sql)?;
        let result = (|| {
            self.bind_text_value(stmt, 1, row.process)?;
            self.bind_text_value(stmt, 2, row.operation)?;
            self.bind_text_value(stmt, 3, row.pattern)?;
            self.bind_text_value(stmt, 4, row.hour)?;
            self.bind_text_value(stmt, 5, row.timestamp)?;
            self.bind_int64_value(stmt, 6, row.pid)?;
            self.bind_text_value(stmt, 7, row.example_path)?;
            self.bind_int64_value(stmt, 8, row.count)?;
            self.expect_done(stmt)
        })();
        unsafe { (self.finalize)(stmt) };
        result
    }

    pub fn migration_complete(&mut self, source: &str) -> Result<bool, String> {
        let stmt = self.prepare("SELECT 1 FROM denial_migrations WHERE source = ?1")?;
        let result = (|| {
            self.bind_text_value(stmt, 1, source)?;
            match unsafe { (self.step)(stmt) } {
                SQLITE_ROW => Ok(true),
                SQLITE_DONE => Ok(false),
                _ => Err(self.err()),
            }
        })();
        unsafe { (self.finalize)(stmt) };
        result
    }

    pub fn mark_migration_complete(&mut self, source: &str) -> Result<(), String> {
        let stmt = self.prepare("INSERT INTO denial_migrations (source) VALUES (?1)")?;
        let result = (|| {
            self.bind_text_value(stmt, 1, source)?;
            self.expect_done(stmt)
        })();
        unsafe { (self.finalize)(stmt) };
        result
    }

    // Keeps only the newest `keep_hours` distinct hour buckets, then reclaims
    // freed pages (auto_vacuum=INCREMENTAL). A cheap no-op while the table is
    // younger than the window, so it can be called on a schedule.
    pub fn trim_old_hours(&mut self, keep_hours: i64) -> Result<(), String> {
        self.exec(&format!(
            "DELETE FROM denials WHERE hour NOT IN \
             (SELECT DISTINCT hour FROM denials ORDER BY hour DESC LIMIT {keep_hours})"
        ))?;
        self.exec("PRAGMA incremental_vacuum")
    }

    // First row of a SELECT as strings (NULL becomes ""). Test helper.
    #[cfg(test)]
    pub(crate) fn query_row(&mut self, sql: &str) -> Result<Vec<String>, String> {
        let stmt = self.prepare(sql)?;
        let rc = unsafe { (self.step)(stmt) };
        if rc == SQLITE_DONE {
            unsafe { (self.finalize)(stmt) };
            return Ok(Vec::new());
        }
        if rc != SQLITE_ROW {
            let e = self.err();
            unsafe { (self.finalize)(stmt) };
            return Err(e);
        }
        let n = unsafe { (self.column_count)(stmt) };
        let mut row = Vec::with_capacity(n.max(0) as usize);
        for i in 0..n {
            let p = unsafe { (self.column_text)(stmt, i) };
            row.push(if p.is_null() {
                String::new()
            } else {
                unsafe { CStr::from_ptr(p) }.to_string_lossy().into_owned()
            });
        }
        unsafe { (self.finalize)(stmt) };
        Ok(row)
    }

    fn bind_text_value(&self, stmt: *mut c_void, index: c_int, value: &str) -> Result<(), String> {
        let c = CString::new(value).map_err(|_| "bind contains NUL".to_string())?;
        let rc = unsafe { (self.bind_text)(stmt, index, c.as_ptr(), -1, SQLITE_TRANSIENT) };
        if rc == SQLITE_OK {
            Ok(())
        } else {
            Err(self.err())
        }
    }

    fn bind_int64_value(&self, stmt: *mut c_void, index: c_int, value: i64) -> Result<(), String> {
        let rc = unsafe { (self.bind_int64)(stmt, index, value) };
        if rc == SQLITE_OK {
            Ok(())
        } else {
            Err(self.err())
        }
    }

    fn expect_done(&self, stmt: *mut c_void) -> Result<(), String> {
        if unsafe { (self.step)(stmt) } == SQLITE_DONE {
            Ok(())
        } else {
            Err(self.err())
        }
    }

    fn prepare(&mut self, sql: &str) -> Result<*mut c_void, String> {
        let c = CString::new(sql).map_err(|_| "sql contains NUL".to_string())?;
        let mut stmt: *mut c_void = std::ptr::null_mut();
        let rc =
            unsafe { (self.prepare)(self.db, c.as_ptr(), -1, &mut stmt, std::ptr::null_mut()) };
        if rc != SQLITE_OK {
            Err(self.err())
        } else if stmt.is_null() {
            Err("sqlite prepare returned null statement".to_string())
        } else {
            Ok(stmt)
        }
    }

    fn err(&self) -> String {
        cstr(unsafe { (self.errmsg)(self.db) })
    }
}

impl Drop for Database {
    fn drop(&mut self) {
        unsafe {
            (self.close)(self.db);
            ffi::dlclose(self.lib);
        }
    }
}

fn cstr(p: *const c_char) -> String {
    if p.is_null() {
        "unknown sqlite error".to_string()
    } else {
        unsafe { CStr::from_ptr(p) }.to_string_lossy().into_owned()
    }
}

#[cfg(test)]
mod tests {
    use super::{Database, DenialRow};
    use std::path::PathBuf;

    fn temp_db(name: &str) -> (PathBuf, Database) {
        let path = std::env::temp_dir().join(format!(
            "aibox-sqlite-test-{name}-{}.db",
            std::process::id()
        ));
        let _ = std::fs::remove_file(&path);
        let db = Database::open(&path).expect("open temp database");
        (path, db)
    }

    fn row<'a>(
        process: &'a str,
        operation: &'a str,
        pattern: &'a str,
        hour: &'a str,
        timestamp: &'a str,
        pid: i64,
        example_path: &'a str,
    ) -> DenialRow<'a> {
        DenialRow {
            process,
            operation,
            pattern,
            hour,
            timestamp,
            pid,
            count: 1,
            example_path,
        }
    }

    #[test]
    fn aggregates_same_pattern_into_one_row() {
        let (path, mut db) = temp_db("agg");
        db.begin().unwrap();
        let pattern = "/Users/eric/repo/.git/objects/\\d+/abcd";
        let example = "/Users/eric/repo/.git/objects/12/abcd";
        db.upsert(&row(
            "git",
            "file-read-data",
            pattern,
            "2026-08-09T15",
            "2026-08-09T15:01:00.001",
            11,
            example,
        ))
        .unwrap();
        db.upsert(&row(
            "git",
            "file-read-data",
            pattern,
            "2026-08-09T15",
            "2026-08-09T15:02:00.002",
            11,
            example,
        ))
        .unwrap();
        db.upsert(&row(
            "git",
            "file-read-data",
            pattern,
            "2026-08-09T15",
            "2026-08-09T15:03:00.003",
            22,
            example,
        ))
        .unwrap();
        db.commit().unwrap();

        let row = db
            .query_row("SELECT count, first_seen, last_seen, last_pid, example_path FROM denials")
            .unwrap();
        assert_eq!(
            row,
            [
                "3",
                "2026-08-09T15:01:00.001",
                "2026-08-09T15:03:00.003",
                "22",
                example
            ]
        );
        drop(db);
        let _ = std::fs::remove_file(&path);
    }

    #[test]
    fn rollback_recovers_after_busy_commit() {
        let (path, mut writer) = temp_db("busy");
        let mut reader = Database::open(&path).unwrap();
        writer.exec("PRAGMA busy_timeout=1").unwrap();
        reader.exec("BEGIN").unwrap();
        reader.query_row("SELECT count(*) FROM denials").unwrap();

        writer.begin().unwrap();
        writer
            .upsert(&row(
                "git",
                "op",
                "/a",
                "2026-08-09T15",
                "2026-08-09T15:00:00.000",
                1,
                "/a",
            ))
            .unwrap();
        assert!(writer.commit().is_err());
        writer.rollback().unwrap();
        reader.rollback().unwrap();

        writer.begin().unwrap();
        writer
            .upsert(&row(
                "git",
                "op",
                "/a",
                "2026-08-09T15",
                "2026-08-09T15:01:00.000",
                2,
                "/a",
            ))
            .unwrap();
        writer.commit().unwrap();
        assert_eq!(
            writer.query_row("SELECT count FROM denials").unwrap(),
            ["1"]
        );
        drop(reader);
        drop(writer);
        let _ = std::fs::remove_file(&path);
    }

    #[test]
    fn trims_old_hour_buckets() {
        let (path, mut db) = temp_db("trim");
        db.begin().unwrap();
        db.upsert(&row(
            "git",
            "op",
            "/a",
            "2026-08-08T10",
            "2026-08-08T10:00:00.000",
            1,
            "/a",
        ))
        .unwrap();
        db.upsert(&row(
            "git",
            "op",
            "/a",
            "2026-08-09T15",
            "2026-08-09T15:00:00.000",
            1,
            "/a",
        ))
        .unwrap();
        db.commit().unwrap();
        db.trim_old_hours(1).unwrap();
        let row = db
            .query_row("SELECT COUNT(*), MAX(hour) FROM denials")
            .unwrap();
        assert_eq!(row, ["1", "2026-08-09T15"]);
        drop(db);
        let _ = std::fs::remove_file(&path);
    }
}
