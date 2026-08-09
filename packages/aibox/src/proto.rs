// Line protocol over the broker<->launcher socketpair and the CLI control
// socket. Messages are newline-terminated; reads and writes go straight through
// raw fds so the same helpers serve both the pollable channel and accepted
// control connections.

use crate::ffi;
use std::io;
use std::os::raw::c_void;

pub fn read_line(fd: i32) -> io::Result<Option<String>> {
    let mut buf: Vec<u8> = Vec::new();
    loop {
        let mut ch = [0u8; 1];
        let n = unsafe { ffi::read(fd, ch.as_mut_ptr() as *mut c_void, 1) };
        if n == 0 {
            return Ok((!buf.is_empty()).then(|| String::from_utf8_lossy(&buf).into_owned()));
        }
        if n < 0 {
            let e = io::Error::last_os_error();
            if e.kind() == io::ErrorKind::Interrupted {
                continue;
            }
            return Err(e);
        }
        if ch[0] == b'\n' {
            break;
        }
        buf.push(ch[0]);
    }
    Ok(Some(String::from_utf8_lossy(&buf).into_owned()))
}

pub fn write_all(fd: i32, s: &str) -> io::Result<()> {
    let b = s.as_bytes();
    let mut off = 0;
    while off < b.len() {
        let n = unsafe { ffi::write(fd, b[off..].as_ptr() as *const c_void, b.len() - off) };
        if n < 0 {
            let e = io::Error::last_os_error();
            if e.kind() == io::ErrorKind::Interrupted {
                continue;
            }
            return Err(e);
        }
        off += n as usize;
    }
    Ok(())
}
