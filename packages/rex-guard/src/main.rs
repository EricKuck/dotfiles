mod filter;
mod json;

use filter::Verdict;
use std::fs;
use std::io::{self, BufRead, BufReader, Read, Write};
use std::net::Shutdown;
use std::os::unix::fs::{DirBuilderExt, PermissionsExt};
use std::os::unix::net::{UnixListener, UnixStream};
use std::path::Path;
use std::process::ExitCode;
use std::sync::{Arc, Mutex};
use std::thread;

const MAX_HEAD_BYTES: usize = 16 * 1024;
const MAX_MESSAGE_BYTES: usize = 1 << 20;
const MAX_CONTROL_BYTES: usize = 125;

const CONTROL_PATH: &str = "/api/control";
const SUBPROTOCOL: &str = "rex.control.v1";

const OP_CONTINUATION: u8 = 0x0;
const OP_TEXT: u8 = 0x1;
const OP_CLOSE: u8 = 0x8;
const OP_PING: u8 = 0x9;
const OP_PONG: u8 = 0xa;

const CLOSE_POLICY_VIOLATION: u16 = 1008;

fn main() -> ExitCode {
    let args: Vec<String> = std::env::args().skip(1).collect();
    let (mut listen, mut upstream) = (None, None);
    let mut it = args.iter();
    while let Some(arg) = it.next() {
        match arg.as_str() {
            "--listen" => listen = it.next().cloned(),
            "--upstream" => upstream = it.next().cloned(),
            _ => {
                listen = None;
                break;
            }
        }
    }
    let (Some(listen), Some(upstream)) = (listen, upstream) else {
        eprintln!("usage: rex-guard --listen SOCKET --upstream SOCKET");
        return ExitCode::from(2);
    };
    match serve(Path::new(&listen), upstream) {
        Ok(()) => ExitCode::SUCCESS,
        Err(err) => {
            eprintln!("rex-guard: {listen}: {err}");
            ExitCode::FAILURE
        }
    }
}

fn serve(listen: &Path, upstream: String) -> io::Result<()> {
    if let Some(dir) = listen.parent() {
        fs::DirBuilder::new().recursive(true).mode(0o700).create(dir)?;
    }
    match fs::remove_file(listen) {
        Err(err) if err.kind() != io::ErrorKind::NotFound => return Err(err),
        _ => {}
    }
    let listener = UnixListener::bind(listen)?;
    fs::set_permissions(listen, fs::Permissions::from_mode(0o600))?;
    let upstream: Arc<str> = upstream.into();
    for client in listener.incoming() {
        let client = client?;
        let upstream = upstream.clone();
        thread::spawn(move || {
            if let Err(err) = handle(client, &upstream) {
                if err.kind() != io::ErrorKind::UnexpectedEof {
                    eprintln!("rex-guard: connection ended: {err}");
                }
            }
        });
    }
    Ok(())
}

fn violation(reason: &'static str) -> io::Error {
    io::Error::new(io::ErrorKind::InvalidData, reason)
}

fn read_head(reader: &mut impl BufRead) -> io::Result<String> {
    let mut head = Vec::new();
    while !head.ends_with(b"\r\n\r\n") {
        let mut line = Vec::new();
        let n = reader.take((MAX_HEAD_BYTES - head.len()) as u64 + 1).read_until(b'\n', &mut line)?;
        if n == 0 {
            return Err(io::ErrorKind::UnexpectedEof.into());
        }
        head.extend_from_slice(&line);
        if head.len() > MAX_HEAD_BYTES {
            return Err(violation("HTTP head too large"));
        }
    }
    String::from_utf8(head).map_err(|_| violation("HTTP head is not UTF-8"))
}

fn header<'a>(head: &'a str, name: &str) -> Option<&'a str> {
    head.lines().skip(1).find_map(|line| {
        let (key, value) = line.split_once(':')?;
        key.trim().eq_ignore_ascii_case(name).then_some(value.trim())
    })
}

// The upgrade is rebuilt rather than relayed, so the server only ever sees the
// control endpoint with no extensions offered, whatever the client sent.
fn upgrade_request(head: &str) -> Option<String> {
    let request_line = head.lines().next()?;
    if request_line != format!("GET {CONTROL_PATH} HTTP/1.1") {
        return None;
    }
    let offers_control = header(head, "sec-websocket-protocol")?
        .split(',')
        .any(|p| p.trim() == SUBPROTOCOL);
    let key = header(head, "sec-websocket-key")?;
    let key_ok = !key.is_empty()
        && key.len() <= 64
        && key.bytes().all(|b| b.is_ascii_alphanumeric() || matches!(b, b'+' | b'/' | b'='));
    (offers_control && key_ok).then(|| {
        format!(
            "GET {CONTROL_PATH} HTTP/1.1\r\nHost: rex\r\nConnection: Upgrade\r\nUpgrade: websocket\r\n\
             Sec-WebSocket-Version: 13\r\nSec-WebSocket-Key: {key}\r\nSec-WebSocket-Protocol: {SUBPROTOCOL}\r\n\r\n"
        )
    })
}

fn refuse(mut client: &UnixStream, status: &str) -> io::Result<()> {
    client.write_all(format!("HTTP/1.1 {status}\r\nConnection: close\r\nContent-Length: 0\r\n\r\n").as_bytes())
}

struct ClientOut {
    stream: UnixStream,
    mid_message: bool,
    pending: Vec<Vec<u8>>,
}

impl ClientOut {
    // A frame of our own cannot go between the fragments of a server message.
    fn send(&mut self, frame: Vec<u8>) -> io::Result<()> {
        if self.mid_message {
            self.pending.push(frame);
            return Ok(());
        }
        self.stream.write_all(&frame)
    }
}

fn handle(client: UnixStream, upstream_path: &str) -> io::Result<()> {
    let mut client_in = BufReader::new(client.try_clone()?);
    let head = read_head(&mut client_in)?;
    let Some(request) = upgrade_request(&head) else {
        eprintln!("rex-guard: refused {:?}", head.lines().next().unwrap_or_default());
        return refuse(&client, "403 Forbidden");
    };
    let Ok(mut upstream) = UnixStream::connect(upstream_path) else {
        return refuse(&client, "502 Bad Gateway");
    };
    upstream.write_all(request.as_bytes())?;
    let mut upstream_in = BufReader::new(upstream.try_clone()?);
    let response = read_head(&mut upstream_in)?;
    (&client).write_all(response.as_bytes())?;
    if !response.starts_with("HTTP/1.1 101 ") || header(&response, "sec-websocket-extensions").is_some() {
        return Ok(());
    }

    let out = Arc::new(Mutex::new(ClientOut {
        stream: client.try_clone()?,
        mid_message: false,
        pending: Vec::new(),
    }));
    let server_side = {
        let out = out.clone();
        let client = client.try_clone()?;
        thread::spawn(move || {
            let _ = relay_server(upstream_in, &out);
            let _ = client.shutdown(Shutdown::Both);
        })
    };
    let result = relay_client(client_in, &upstream, &out);
    if let Err(err) = &result {
        if err.kind() == io::ErrorKind::InvalidData {
            let mut payload = CLOSE_POLICY_VIOLATION.to_be_bytes().to_vec();
            payload.extend_from_slice(err.to_string().as_bytes());
            let _ = out.lock().unwrap().send(encode_frame(OP_CLOSE, &payload, false));
        }
        let _ = upstream.shutdown(Shutdown::Both);
    }
    let _ = server_side.join();
    let _ = client.shutdown(Shutdown::Both);
    result
}

fn encode_frame(opcode: u8, payload: &[u8], masked: bool) -> Vec<u8> {
    let mask_bit = if masked { 0x80 } else { 0 };
    let mut frame = vec![0x80 | opcode];
    match payload.len() {
        n if n < 126 => frame.push(mask_bit | n as u8),
        n if n <= u16::MAX as usize => {
            frame.push(mask_bit | 126);
            frame.extend_from_slice(&(n as u16).to_be_bytes());
        }
        n => {
            frame.push(mask_bit | 127);
            frame.extend_from_slice(&(n as u64).to_be_bytes());
        }
    }
    if masked {
        // An all-zero key is a valid mask and leaves the payload as it is.
        frame.extend_from_slice(&[0; 4]);
    }
    frame.extend_from_slice(payload);
    frame
}

struct Frame {
    fin: bool,
    opcode: u8,
    payload: Vec<u8>,
}

fn read_client_frame(reader: &mut impl Read) -> io::Result<Frame> {
    let mut head = [0u8; 2];
    reader.read_exact(&mut head)?;
    if head[0] & 0x70 != 0 {
        return Err(violation("reserved bits set"));
    }
    if head[1] & 0x80 == 0 {
        return Err(violation("unmasked client frame"));
    }
    let len = match head[1] & 0x7f {
        126 => {
            let mut ext = [0u8; 2];
            reader.read_exact(&mut ext)?;
            u16::from_be_bytes(ext) as u64
        }
        127 => {
            let mut ext = [0u8; 8];
            reader.read_exact(&mut ext)?;
            u64::from_be_bytes(ext)
        }
        n => n as u64,
    };
    if len > MAX_MESSAGE_BYTES as u64 {
        return Err(violation("frame too large"));
    }
    let mut key = [0u8; 4];
    reader.read_exact(&mut key)?;
    let mut payload = vec![0u8; len as usize];
    reader.read_exact(&mut payload)?;
    for (i, byte) in payload.iter_mut().enumerate() {
        *byte ^= key[i % 4];
    }
    Ok(Frame { fin: head[0] & 0x80 != 0, opcode: head[0] & 0x0f, payload })
}

fn relay_client(mut client: impl Read, mut upstream: &UnixStream, out: &Mutex<ClientOut>) -> io::Result<()> {
    let mut message: Option<Vec<u8>> = None;
    let mut first = true;
    loop {
        let frame = read_client_frame(&mut client)?;
        match frame.opcode {
            OP_CLOSE | OP_PING | OP_PONG => {
                if !frame.fin || frame.payload.len() > MAX_CONTROL_BYTES {
                    return Err(violation("malformed control frame"));
                }
                upstream.write_all(&encode_frame(frame.opcode, &frame.payload, true))?;
                if frame.opcode == OP_CLOSE {
                    return Ok(());
                }
                continue;
            }
            OP_TEXT if message.is_none() => message = Some(frame.payload),
            OP_CONTINUATION => {
                let Some(buffer) = message.as_mut() else {
                    return Err(violation("continuation without a message"));
                };
                if buffer.len() + frame.payload.len() > MAX_MESSAGE_BYTES {
                    return Err(violation("message too large"));
                }
                buffer.extend_from_slice(&frame.payload);
            }
            _ => return Err(violation("unexpected frame")),
        }
        if !frame.fin {
            continue;
        }
        let bytes = message.take().unwrap_or_default();
        let text = String::from_utf8(bytes).map_err(|_| violation("message is not UTF-8"))?;
        match filter::check(&text, first) {
            Verdict::Forward(text) => upstream.write_all(&encode_frame(OP_TEXT, text.as_bytes(), true))?,
            Verdict::Deny { id, reason } => {
                eprintln!("rex-guard: denied: {reason}");
                let reply = filter::denial(&id, &reason);
                out.lock().unwrap().send(encode_frame(OP_TEXT, reply.as_bytes(), false))?;
            }
            Verdict::Reject(reason) => return Err(violation(reason)),
        }
        first = false;
    }
}

fn relay_server(mut upstream: impl Read, out: &Mutex<ClientOut>) -> io::Result<()> {
    loop {
        let mut head = [0u8; 14];
        upstream.read_exact(&mut head[..2])?;
        let mut head_len = 2 + match head[1] & 0x7f {
            126 => 2,
            127 => 8,
            _ => 0,
        };
        upstream.read_exact(&mut head[2..head_len])?;
        let len = match head[1] & 0x7f {
            126 => u16::from_be_bytes([head[2], head[3]]) as u64,
            127 => u64::from_be_bytes(head[2..10].try_into().unwrap()),
            n => n as u64,
        };
        if head[1] & 0x80 != 0 {
            upstream.read_exact(&mut head[head_len..head_len + 4])?;
            head_len += 4;
        }

        let mut guard = out.lock().unwrap();
        let out = &mut *guard;
        out.stream.write_all(&head[..head_len])?;
        if io::copy(&mut (&mut upstream).take(len), &mut out.stream)? != len {
            return Err(io::ErrorKind::UnexpectedEof.into());
        }
        if head[0] & 0x08 == 0 {
            out.mid_message = head[0] & 0x80 == 0;
        }
        if !out.mid_message {
            for frame in std::mem::take(&mut out.pending) {
                out.stream.write_all(&frame)?;
            }
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn head(lines: &[&str]) -> String {
        lines.iter().map(|l| format!("{l}\r\n")).collect::<String>() + "\r\n"
    }

    #[test]
    fn upgrade_is_rebuilt_without_extensions() {
        let request = upgrade_request(&head(&[
            "GET /api/control HTTP/1.1",
            "Sec-Websocket-Extensions: permessage-deflate",
            "Sec-Websocket-Key: iNmwVtkFRmH6gQ254AgRGg==",
            "Sec-Websocket-Protocol: rex.control.v1",
            "X-Anything: else",
        ]))
        .expect("accepted");
        assert!(request.contains("Sec-WebSocket-Key: iNmwVtkFRmH6gQ254AgRGg==\r\n"));
        assert!(!request.to_ascii_lowercase().contains("extensions"));
        assert!(!request.contains("X-Anything"));
    }

    #[test]
    fn only_the_control_endpoint_upgrades() {
        for lines in [
            &["GET /api/data HTTP/1.1", "Sec-Websocket-Key: abc=", "Sec-Websocket-Protocol: rex.control.v1"][..],
            &["GET /api/control?x HTTP/1.1", "Sec-Websocket-Key: abc=", "Sec-Websocket-Protocol: rex.control.v1"],
            &["POST /api/control HTTP/1.1", "Sec-Websocket-Key: abc=", "Sec-Websocket-Protocol: rex.control.v1"],
            &["GET /api/control HTTP/1.1", "Sec-Websocket-Key: abc=", "Sec-Websocket-Protocol: rex.data.terminal.v1"],
            &["GET /api/control HTTP/1.1", "Sec-Websocket-Key: a b", "Sec-Websocket-Protocol: rex.control.v1"],
            &["GET /api/control HTTP/1.1", "Sec-Websocket-Protocol: rex.control.v1"],
        ] {
            assert_eq!(upgrade_request(&head(lines)), None, "{lines:?}");
        }
    }

    fn masked(first: u8, payload: &[u8]) -> Vec<u8> {
        let key = [0x11, 0x22, 0x33, 0x44];
        let mut frame = vec![first, 0x80 | payload.len() as u8];
        frame.extend_from_slice(&key);
        frame.extend(payload.iter().enumerate().map(|(i, b)| b ^ key[i % 4]));
        frame
    }

    #[test]
    fn client_frames_are_unmasked_and_checked() {
        let frame = read_client_frame(&mut &masked(0x81, b"hello")[..]).expect("frame");
        assert!(frame.fin);
        assert_eq!(frame.opcode, OP_TEXT);
        assert_eq!(frame.payload, b"hello");

        assert!(read_client_frame(&mut &masked(0xc1, b"compressed")[..]).is_err());
        assert!(read_client_frame(&mut &[0x81, 0x02, b'h', b'i'][..]).is_err());
        let huge = [&[0x81, 0xff][..], &u64::MAX.to_be_bytes()].concat();
        assert!(read_client_frame(&mut &huge[..]).is_err());
    }

    #[test]
    fn encoded_frames_carry_their_length() {
        assert_eq!(encode_frame(OP_TEXT, b"hi", false), [0x81, 0x02, b'h', b'i']);
        assert_eq!(encode_frame(OP_TEXT, b"hi", true), [0x81, 0x82, 0, 0, 0, 0, b'h', b'i']);
        assert_eq!(encode_frame(OP_TEXT, &[0; 300], false)[..4], [0x81, 126, 0x01, 0x2c]);
        assert_eq!(encode_frame(OP_TEXT, &[0; 70_000], false)[..2], [0x81, 127]);
    }
}
