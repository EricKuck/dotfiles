// Thin wrapper over the private sandbox-extension functions, resolved at
// runtime with dlsym (they are not declared in the public <sandbox.h>).
//
// Verified behavior these rely on (macOS 26.6): an unentitled process can issue
// a read-write token for any directory it can reach; a sandboxed process that
// consumes the token gains access live, shared across its sandbox label, and
// releasing the handle revokes it.

use crate::ffi;
use std::ffi::{CStr, CString};
use std::os::raw::{c_char, c_void};

pub const EXT_CLASS: &str = "com.apple.app-sandbox.read-write";

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
            let tok = f(cls.as_ptr(), p.as_ptr(), 0);
            if tok.is_null() {
                return None;
            }
            let s = CStr::from_ptr(tok).to_string_lossy().into_owned();
            ffi::free(tok as *mut c_void);
            Some(s)
        }
    }

    // Consumes a token, returning the handle used to release it later. Runs
    // INSIDE the sandbox.
    pub fn consume(&self, token: &str) -> Option<i64> {
        let f = self.consume?;
        let t = CString::new(token).ok()?;
        let h = unsafe { f(t.as_ptr()) };
        (h >= 0).then_some(h)
    }

    pub fn release(&self, handle: i64) {
        if let Some(f) = self.release {
            unsafe {
                f(handle);
            }
        }
    }
}
