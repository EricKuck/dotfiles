// The slice of libc/libdyld we need, declared directly so the crate carries no
// dependencies and builds offline. Values are the macOS (BSD) ABI constants.
#![allow(non_camel_case_types)]

use std::os::raw::{c_char, c_int, c_short, c_uint, c_void};

pub type size_t = usize;
pub type ssize_t = isize;

pub const AF_UNIX: c_int = 1;
pub const SOCK_STREAM: c_int = 1;
pub const POLLIN: c_short = 0x0001;
pub const POLLERR: c_short = 0x0008;
pub const POLLHUP: c_short = 0x0010;
pub const F_SETFD: c_int = 2;
pub const FD_CLOEXEC: c_int = 1;
pub const SIGPIPE: c_int = 13;
pub const SIG_IGN: usize = 1;
pub const LOCK_EX: c_int = 2;
pub const LOCK_NB: c_int = 4;
pub const LOCK_UN: c_int = 8;

#[repr(C)]
pub struct pollfd {
    pub fd: c_int,
    pub events: c_short,
    pub revents: c_short,
}

// RTLD_DEFAULT is a sentinel pointer, not a real handle; integer-to-pointer
// casts aren't allowed in const context, so compute it at call time.
pub fn rtld_default() -> *mut c_void {
    -2isize as *mut c_void
}

pub const RTLD_NOW: c_int = 0x2;

// Loading a dylib by absolute path (e.g. /usr/lib/libsqlite3.dylib for the
// denial database) keeps the crate dependency-free and builds offline.
pub fn dlopen(path: *const c_char, mode: c_int) -> *mut c_void {
    extern "C" {
        fn dlopen(path: *const c_char, mode: c_int) -> *mut c_void;
    }
    unsafe { dlopen(path, mode) }
}

pub fn dlclose(handle: *mut c_void) -> c_int {
    extern "C" {
        fn dlclose(handle: *mut c_void) -> c_int;
    }
    unsafe { dlclose(handle) }
}

extern "C" {
    pub fn socketpair(domain: c_int, ty: c_int, protocol: c_int, sv: *mut c_int) -> c_int;
    pub fn pipe(fds: *mut c_int) -> c_int;
    pub fn poll(fds: *mut pollfd, nfds: c_uint, timeout: c_int) -> c_int;
    pub fn dlsym(handle: *mut c_void, symbol: *const c_char) -> *mut c_void;
    pub fn read(fd: c_int, buf: *mut c_void, count: size_t) -> ssize_t;
    pub fn write(fd: c_int, buf: *const c_void, count: size_t) -> ssize_t;
    pub fn close(fd: c_int) -> c_int;
    pub fn fcntl(fd: c_int, cmd: c_int, arg: c_int) -> c_int;
    pub fn flock(fd: c_int, operation: c_int) -> c_int;
    pub fn free(ptr: *mut c_void);
    pub fn signal(sig: c_int, handler: usize) -> usize;
}

pub fn set_cloexec(fd: c_int) {
    unsafe {
        fcntl(fd, F_SETFD, FD_CLOEXEC);
    }
}
