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
    pub fn load() -> Self {
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
    pub fn issue(&self, path: &str) -> Option<String> {
        let f = self.issue?;
        let cls = CString::new(EXT_CLASS).ok()?;
        let p = CString::new(path).ok()?;
        unsafe {
            let tok = f(cls.as_ptr(), p.as_ptr(), ISSUE_FLAGS);
            if tok.is_null() {
                return None;
            }
            let s = CStr::from_ptr(tok).to_string_lossy().into_owned();
            ffi::free(tok as *mut c_void);
            Some(s)
        }
    }

    // Consumes a token, returning the handle used to release it later. Runs
    // INSIDE the sandbox. Returns Err(errno) on failure.
    pub fn consume(&self, token: &str) -> Result<i64, i32> {
        let f = self.consume.ok_or(0)?;
        let t = CString::new(token).map_err(|_| 0)?;
        let h = unsafe { f(t.as_ptr()) };
        if h >= 0 {
            Ok(h)
        } else {
            // Capture errno immediately before any other syscall can reset it.
            Err(IoError::last_os_error().raw_os_error().unwrap_or(-1))
        }
    }

    pub fn release(&self, handle: i64) {
        if let Some(f) = self.release {
            unsafe {
                f(handle);
            }
        }
    }
}
