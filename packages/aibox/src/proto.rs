// Line protocol over the broker<->launcher socketpair and the CLI control
// socket. Messages are newline-terminated; reads and writes go straight through
// raw fds so the same helpers serve both the pollable channel and accepted
// control connections.

use crate::ffi;
use std::io;
use std::os::raw::c_void;

// Extension tokens are opaque capability strings, issued by the kernel with
// the target path embedded verbatim (semicolon-delimited fields). A token for
// a path containing spaces therefore contains spaces itself, yet the CONSUME
// line is "<token> <dir...>" with dirs allowed to contain spaces too -- the
// only unambiguous layout is a token alphabet with no spaces. Carrying the
// token base64-encoded keeps the first-space split exact on both sides.
const B64: &[u8; 64] = b"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";

pub fn b64_encode(data: &[u8]) -> String {
    let mut out = String::with_capacity(data.len().div_ceil(3) * 4);
    for chunk in data.chunks(3) {
        let b0 = chunk[0];
        let b1 = *chunk.get(1).unwrap_or(&0);
        let b2 = *chunk.get(2).unwrap_or(&0);
        let n = ((b0 as u32) << 16) | ((b1 as u32) << 8) | b2 as u32;
        out.push(B64[(n >> 18) as usize & 0x3f] as char);
        out.push(B64[(n >> 12) as usize & 0x3f] as char);
        out.push(if chunk.len() > 1 { B64[(n >> 6) as usize & 0x3f] as char } else { '=' });
        out.push(if chunk.len() > 2 { B64[n as usize & 0x3f] as char } else { '=' });
    }
    out
}

pub fn b64_decode(s: &str) -> Option<Vec<u8>> {
    let bytes = s.as_bytes();
    if bytes.len() % 4 != 0 {
        return None;
    }
    let mut out = Vec::with_capacity(bytes.len() / 4 * 3);
    let mut i = 0;
    while i < bytes.len() {
        let (mut n, mut pad) = (0u32, 0);
        for k in 0..4 {
            let c = bytes[i + k];
            let v = match c {
                b'A'..=b'Z' => c - b'A',
                b'a'..=b'z' => c - b'a' + 26,
                b'0'..=b'9' => c - b'0' + 52,
                b'+' => 62,
                b'/' => 63,
                b'=' => {
                    pad += 1;
                    0
                }
                _ => return None,
            };
            if k == 3 && pad > 2 {
                return None;
            }
            n = (n << 6) | v as u32;
        }
        out.push((n >> 16) as u8);
        if pad < 2 {
            out.push((n >> 8) as u8);
        }
        if pad < 1 {
            out.push(n as u8);
        }
        i += 4;
    }
    Some(out)
}

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

#[cfg(test)]
mod tests {
    use super::{b64_decode, b64_encode};
    use crate::proto::{read_line, write_all};

    #[test]
    fn base64_roundtrips_bytes() {
        let cases: &[&[u8]] = &[b"", b"f", b"fo", b"foo", b"foob", b"fooba", b"foobar"];
        for c in cases {
            assert_eq!(b64_decode(&b64_encode(c)).as_deref(), Some(*c), "{c:?}");
        }
    }

    // The reason the transport encodes: a token for a spaced path embeds the
    // path, spaces included, and the CONSUME line splits on the first space.
    #[test]
    fn base64_never_contains_spaces() {
        let embeds = b";IL:1;com.apple.app-sandbox.read-write;...;/Users/eric/Library/Application Support/kotlin";
        let tok = b64_encode(embeds);
        assert!(embeds.iter().any(|b| *b == b' '));
        assert!(!tok.contains(' '));
        assert!(!tok.contains(';'));
    }

    #[test]
    fn base64_rejects_junk() {
        assert!(b64_decode("nope!").is_none());
        assert!(b64_decode("AA").is_none());
        assert!(b64_decode("====").is_none());
    }

    #[test]
    fn line_roundtrip_over_a_pipe() {
        let mut fds = [0i32; 2];
        unsafe {
            crate::ffi::pipe(fds.as_mut_ptr());
        }
        let (r, w) = (fds[0], fds[1]);
        let _ = write_all(w, "CONSUME dG9rZW4= /Users/eric/Library/Application Support/kotlin\n");
        let line = read_line(r).unwrap().expect("line");
        // Mirror handle_line: the verb "CONSUME " is stripped before splitting.
        let rest = line.strip_prefix("CONSUME ").unwrap();
        let (b64, dir) = rest.split_once(' ').unwrap();
        assert_eq!(b64_decode(b64).as_deref(), Some(&b"token"[..]));
        assert_eq!(dir, "/Users/eric/Library/Application Support/kotlin");
        unsafe {
            crate::ffi::close(r);
            crate::ffi::close(w);
        }
    }
}



