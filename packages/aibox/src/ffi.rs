// The slice of libc/libdyld we need, declared directly so the crate carries no
// dependencies and builds offline. The constants below hold on both supported
// platforms; the ones that do not are in the per-platform block at the end.
#![allow(non_camel_case_types)]

use std::os::raw::{c_char, c_int, c_short, c_uint, c_void};
#[cfg(target_os = "linux")]
use std::os::raw::c_ulong;

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
// Only the denial logger's writer election takes a lock, and only macOS has
// denials to log.
#[cfg(target_os = "macos")]
pub const LOCK_EX: c_int = 2;
#[cfg(target_os = "macos")]
pub const LOCK_NB: c_int = 4;
#[cfg(target_os = "macos")]
pub const LOCK_UN: c_int = 8;

#[repr(C)]
pub struct pollfd {
    pub fd: c_int,
    pub events: c_short,
    pub revents: c_short,
}

// The dynamic-linker slice, used only where a symbol is resolved at runtime:
// the private sandbox-extension functions and libsqlite3, both macOS-only.
#[cfg(target_os = "macos")]
mod dyld {
    use super::{c_char, c_int, c_void};

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
        pub fn dlsym(handle: *mut c_void, symbol: *const c_char) -> *mut c_void;
        pub fn flock(fd: c_int, operation: c_int) -> c_int;
        pub fn free(ptr: *mut c_void);
    }
}

#[cfg(target_os = "macos")]
pub use dyld::*;

extern "C" {
    pub fn socketpair(domain: c_int, ty: c_int, protocol: c_int, sv: *mut c_int) -> c_int;
    pub fn poll(fds: *mut pollfd, nfds: c_uint, timeout: c_int) -> c_int;
    pub fn read(fd: c_int, buf: *mut c_void, count: size_t) -> ssize_t;
    pub fn write(fd: c_int, buf: *const c_void, count: size_t) -> ssize_t;
    pub fn close(fd: c_int) -> c_int;
    pub fn fcntl(fd: c_int, cmd: c_int, arg: c_int) -> c_int;
    pub fn signal(sig: c_int, handler: usize) -> usize;
}

// Used by the protocol's own round-trip test.
#[cfg(test)]
extern "C" {
    pub fn pipe(fds: *mut c_int) -> c_int;
}

pub fn set_cloexec(fd: c_int) {
    unsafe {
        fcntl(fd, F_SETFD, FD_CLOEXEC);
    }
}

// The mount and namespace calls the Linux sandbox is built out of. Live grants
// are bind mounts propagated between namespaces, so these are the equivalent
// of the sandbox-extension functions dlsym'd on macOS.
#[cfg(target_os = "linux")]
mod linux {
    use super::{c_char, c_int, c_ulong, c_void};

    pub const CLONE_NEWNS: c_int = 0x0002_0000;
    pub const CLONE_NEWUSER: c_int = 0x1000_0000;

    pub const MS_BIND: c_ulong = 1 << 12;
    pub const MS_REC: c_ulong = 1 << 14;
    pub const MS_SLAVE: c_ulong = 1 << 19;
    pub const MS_SHARED: c_ulong = 1 << 20;

    // Detach the mount now and tear it down once nothing is using it.
    pub const MNT_DETACH: c_int = 2;

    extern "C" {
        pub fn unshare(flags: c_int) -> c_int;
        pub fn mount(
            source: *const c_char,
            target: *const c_char,
            fstype: *const c_char,
            flags: c_ulong,
            data: *const c_void,
        ) -> c_int;
        pub fn umount2(target: *const c_char, flags: c_int) -> c_int;
        pub fn getuid() -> u32;
        pub fn getgid() -> u32;
    }
}

#[cfg(target_os = "linux")]
pub use linux::*;
