// Thin wrapper over the private sandbox-extension functions, resolved at
// runtime with dlsym (they are not declared in the public <sandbox.h>).
//
// Verified behavior these rely on (macOS 26.6): an unentitled process can issue
// a read-write token for any directory it can reach; a sandboxed process that
// consumes the token gains access live, shared across its sandbox label, and
// releasing the handle revokes it.

use crate::ffi;
use std::ffi::{CStr, CString};
use std::io::Error as IoError;
use std::os::raw::{c_char, c_void};
use std::path::Path;
use std::process::Command;

pub const EXT_CLASS: &str = "com.apple.app-sandbox.read-write";

// Issue flags for sandbox_extension_issue_file (Apple's sandbox.h):
// SANDBOX_EXTENSION_DEFAULT (0x0000) leaves the token path as given;
// SANDBOX_EXTENSION_CANONICAL (0x0001) has the kernel realpath() it first.
const SANDBOX_EXTENSION_DEFAULT: u32 = 0x0000;
// Documented for anyone tempted to "fix" the flag: the value comes from
// Apple's sandbox.h, kept for reference, deliberately NOT applied.
#[allow(dead_code)]
const SANDBOX_EXTENSION_CANONICAL: u32 = 0x0001;

// CANONICAL must not be used: the kernel's canonicalization expands firmlinks
// (on this machine /Users is a firmlink to /System/Volumes/Data/Users), so a
// token issued for /Users/eric/<dir> embeds the data-volume path instead. The
// sandboxed process accesses the path through the firmlink spelling, the
// extension check finds no match, and the grant silently never applies --
// consume reports OK but the directory stays denied. This regressed live
// `aibox allow` (and manifest re-grants for every later session) for ALL
// paths under /Users.
//
// The issuer already hands over a symlink-resolved path (broker::allow runs
// std::fs::canonicalize before issue), so DEFAULT is both necessary and
// sufficient: the token carries exactly the path the sandboxed process will
// access.
const ISSUE_FLAGS: u32 = SANDBOX_EXTENSION_DEFAULT;

type IssueFn = unsafe extern "C" fn(*const c_char, *const c_char, u32) -> *mut c_char;
type ConsumeFn = unsafe extern "C" fn(*const c_char) -> i64;
type ReleaseFn = unsafe extern "C" fn(i64) -> i32;

pub struct Sandbox {
    issue: Option<IssueFn>,
    consume: Option<ConsumeFn>,
    release: Option<ReleaseFn>,
}

fn sym(name: &str) -> *mut c_void {
    let c = CString::new(name).unwrap();
    unsafe { ffi::dlsym(ffi::rtld_default(), c.as_ptr()) }
}

impl Sandbox {
    // The broker's side, outside the sandbox: only an unsandboxed process may
    // issue tokens.
    pub fn host() -> Result<Self, String> {
        Ok(Self::load())
    }

    // The launcher's side, inside the sandbox.
    pub fn guest() -> Result<Self, String> {
        Ok(Self::load())
    }

    // The sandboxed session: sandbox-exec applies the profile to the launcher
    // and everything it spawns.
    pub fn session_command(
        &self,
        profile: &Path,
        launcher: &Path,
        harness: &[String],
    ) -> Result<Command, String> {
        let mut c = Command::new("/usr/bin/sandbox-exec");
        c.arg("-f")
            .arg(profile)
            .arg(launcher)
            .arg("launch")
            .arg("--")
            .args(harness);
        Ok(c)
    }

    fn load() -> Self {
        let i = sym("sandbox_extension_issue_file");
        let c = sym("sandbox_extension_consume");
        let r = sym("sandbox_extension_release");
        unsafe {
            Sandbox {
                issue: (!i.is_null()).then(|| std::mem::transmute::<*mut c_void, IssueFn>(i)),
                consume: (!c.is_null()).then(|| std::mem::transmute::<*mut c_void, ConsumeFn>(c)),
                release: (!r.is_null()).then(|| std::mem::transmute::<*mut c_void, ReleaseFn>(r)),
            }
        }
    }

    // Issues a read-write token for path. Must run OUTSIDE the sandbox.
    pub fn issue(&self, path: &str) -> Result<String, String> {
        let f = self.issue.ok_or("sandbox_extension_issue_file unavailable")?;
        let cls = CString::new(EXT_CLASS).map_err(|e| e.to_string())?;
        let p = CString::new(path).map_err(|e| e.to_string())?;
        unsafe {
            let tok = f(cls.as_ptr(), p.as_ptr(), ISSUE_FLAGS);
            if tok.is_null() {
                return Err(format!("issue failed for {path}"));
            }
            let s = CStr::from_ptr(tok).to_string_lossy().into_owned();
            ffi::free(tok as *mut c_void);
            Ok(s)
        }
    }

    // Nothing outside the sandbox holds state for a grant: the token is
    // consumed by the launcher, which is also what releases it.
    pub fn revoke(&self, _dir: &str) {}

    // Consumes a token, returning the handle used to release it later. Runs
    // INSIDE the sandbox. The directory is not needed here -- the token
    // carries it -- but the Linux side binds onto it, so both take it.
    pub fn consume(&self, token: &str, _dir: &str) -> Result<i64, String> {
        let f = self
            .consume
            .ok_or("sandbox_extension_consume unavailable")?;
        let t = CString::new(token).map_err(|e| e.to_string())?;
        let h = unsafe { f(t.as_ptr()) };
        if h >= 0 {
            Ok(h)
        } else {
            // Capture errno immediately before any other syscall can reset it.
            let errno = IoError::last_os_error().raw_os_error().unwrap_or(-1);
            Err(format!("errno={errno}"))
        }
    }

    pub fn release(&self, handle: i64, _dir: &str) {
        if let Some(f) = self.release {
            unsafe {
                f(handle);
            }
        }
    }
}
