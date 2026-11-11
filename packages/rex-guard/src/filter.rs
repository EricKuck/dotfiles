use crate::json::{self, Json};

const ALLOWED_METHODS: &[&str] = &[
    "server.status",
    "server.version",
    "server.whoami",
    "help.all",
    "block_creator.list",
    "client.inspect",
    "client.list",
    "target.complete",
    "target.resolve",
    "session.attach",
    "session.attach_all",
    "session.bootstrap",
    "session.detach",
    "session.describe_block",
    "session.help",
    "session.list",
    "session.list_blocks",
    "session.list_clients",
    "session.view",
    "session.focus_block",
    "session.focus_direction",
    "session.focus_next_pane",
    "session.focus_next_window",
    "session.focus_previous_pane",
    "session.focus_previous_window",
    "session.focus_window",
    "session.zoom_block",
    "block.method",
];

// list_dir and clipboard_read are left out: they read the host's filesystem
// and clipboard rather than a pane.
const ALLOWED_BLOCK_METHODS: &[&str] = &[
    "blob_read",
    "format",
    "input_mode",
    "modes",
    "process",
    "program_status",
    "pwd",
    "size",
    "title",
];

// The server's decoder matches keys case-insensitively, so every object whose
// keys decide the verdict is held to an exact key set.
const HELLO_KEYS: &[&str] = &["type", "client", "api_revision"];
const REQUEST_KEYS: &[&str] = &["type", "id", "method", "payload"];
const BLOCK_METHOD_KEYS: &[&str] = &["session_id", "block_id", "method", "args"];
// data_tickets is left out: it issues the same tickets as data.connect.
const BOOTSTRAP_KEYS: &[&str] = &["event_scope", "attach_session_ids", "preferred_session_id"];

const MAX_ID_BYTES: usize = 256;

#[derive(Debug, PartialEq)]
pub enum Verdict {
    Forward(String),
    Deny { id: String, reason: String },
    Reject(&'static str),
}

fn only_keys(value: &Json, allowed: &[&str]) -> bool {
    value.keys().is_some_and(|mut keys| keys.all(|k| allowed.contains(&k)))
}

pub fn check(text: &str, first: bool) -> Verdict {
    let Some(message) = json::parse(text) else {
        return Verdict::Reject("malformed message");
    };
    let kind = message.get("type").and_then(Json::as_str);
    if first {
        if kind != Some("hello") || !only_keys(&message, HELLO_KEYS) {
            return Verdict::Reject("unexpected hello");
        }
        return forward(&message);
    }
    if kind != Some("request") || !only_keys(&message, REQUEST_KEYS) {
        return Verdict::Reject("unexpected message");
    }
    let Some(id) = message.get("id").and_then(Json::as_str).filter(|id| id.len() <= MAX_ID_BYTES) else {
        return Verdict::Reject("request without a usable id");
    };
    let Some(method) = message.get("method").and_then(Json::as_str) else {
        return Verdict::Reject("request without a method");
    };
    let deny = |reason: String| Verdict::Deny { id: id.to_string(), reason };
    if !ALLOWED_METHODS.contains(&method) {
        return deny(format!("method {method:?} is not allowed from the sandbox"));
    }
    let payload = message.get("payload");
    match method {
        "block.method" => {
            let inner = payload
                .filter(|p| only_keys(p, BLOCK_METHOD_KEYS))
                .and_then(|p| p.get("method"))
                .and_then(Json::as_str);
            match inner {
                Some(inner) if ALLOWED_BLOCK_METHODS.contains(&inner) => {}
                Some(inner) => {
                    return deny(format!("block method {inner:?} is not allowed from the sandbox"))
                }
                None => return deny("block.method payload is not allowed from the sandbox".to_string()),
            }
        }
        "session.bootstrap" if !payload.is_some_and(|p| only_keys(p, BOOTSTRAP_KEYS)) => {
            return deny("session.bootstrap with data tickets is not allowed from the sandbox".to_string());
        }
        _ => {}
    }
    forward(&message)
}

fn forward(message: &Json) -> Verdict {
    let mut out = String::new();
    message.write(&mut out);
    Verdict::Forward(out)
}

pub fn denial(id: &str, reason: &str) -> String {
    let mut out = String::from("{\"type\":\"response\",\"id\":");
    json::write_str(id, &mut out);
    out.push_str(",\"seq\":0,\"error\":{\"code\":\"forbidden\",\"message\":");
    json::write_str(&format!("rex-guard: {reason}"), &mut out);
    out.push_str(",\"status\":403}}");
    out
}

#[cfg(test)]
mod tests {
    use super::*;

    fn request(method: &str, payload: &str) -> Verdict {
        check(
            &format!(r#"{{"type":"request","id":"control-1","method":"{method}","payload":{payload}}}"#),
            false,
        )
    }

    fn forwarded(verdict: Verdict) -> bool {
        matches!(verdict, Verdict::Forward(_))
    }

    fn denied(verdict: Verdict) -> bool {
        matches!(verdict, Verdict::Deny { .. })
    }

    #[test]
    fn hello_only_comes_first() {
        let hello = r#"{"type":"hello","client":{"kind":"cli"},"api_revision":10}"#;
        assert!(forwarded(check(hello, true)));
        assert!(matches!(check(hello, false), Verdict::Reject(_)));
        assert!(matches!(
            check(r#"{"type":"request","id":"1","method":"server.status"}"#, true),
            Verdict::Reject(_)
        ));
        assert!(matches!(
            check(r#"{"type":"hello","reconnect_token":"x"}"#, true),
            Verdict::Reject(_)
        ));
    }

    #[test]
    fn reads_pass_and_escapes_do_not() {
        for method in ["server.status", "session.view", "session.attach", "target.resolve", "session.zoom_block"] {
            assert!(forwarded(request(method, "{}")), "{method}");
        }
        for method in [
            "session.new_window",
            "session.new_split",
            "session.new_block",
            "session.new_layer",
            "session.create",
            "block.event",
            "client.key",
            "client.action",
            "client.perform",
            "client.reply",
            "client.set_script",
            "data.connect",
            "server.stop",
            "server.config_reload",
            "server.tailscale.enable",
            "server.apple.grant_file_access",
            "hosts.put",
            "hosts.remove",
            "some.future.method",
            "Server.Status",
            "server.status ",
        ] {
            assert!(denied(request(method, "{}")), "{method}");
        }
    }

    #[test]
    fn block_method_is_filtered_by_inner_method() {
        assert!(forwarded(request(
            "block.method",
            r#"{"session_id":"s","block_id":"b","method":"format","args":{"format":"text"}}"#
        )));
        for payload in [
            r#"{"session_id":"s","block_id":"b","method":"write","args":{"text":"id\n"}}"#,
            r#"{"session_id":"s","block_id":"b","method":"upload_begin"}"#,
            r#"{"session_id":"s","block_id":"b","method":"list_dir"}"#,
            r#"{"session_id":"s","block_id":"b","method":"com.superlogical.terminal.write"}"#,
            r#"{"session_id":"s","block_id":"b","method":"format","Method":"write"}"#,
            r#"{"session_id":"s","block_id":"b","method":"format","METHOD":"write"}"#,
            r#"{"session_id":"s","block_id":"b"}"#,
            r#"{"session_id":"s","block_id":"b","method":["format"]}"#,
            r#"["format"]"#,
        ] {
            assert!(denied(request("block.method", payload)), "{payload}");
        }
        assert!(denied(check(r#"{"type":"request","id":"1","method":"block.method"}"#, false)));
    }

    #[test]
    fn bootstrap_cannot_ask_for_data_tickets() {
        assert!(forwarded(request("session.bootstrap", r#"{"event_scope":"session"}"#)));
        assert!(denied(request(
            "session.bootstrap",
            r#"{"event_scope":"session","data_tickets":[{"creator_name":"com.superlogical.terminal","data_ref_id":"terminal"}]}"#
        )));
    }

    #[test]
    fn decoder_differentials_are_rejected() {
        for text in [
            r#"{"type":"request","id":"1","method":"server.status","method":"block.event"}"#,
            r#"{"type":"request","id":"1","method":"server.status","Method":"block.event"}"#,
            r#"{"type":"request","id":"1","method":"server.status","METHOD":"block.event"}"#,
            r#"{"type":"request","Type":"hello","id":"1","method":"server.status"}"#,
            r#"{"type":"request","id":1,"method":"server.status"}"#,
            r#"{"type":"request","id":"1"}"#,
            r#"{"type":"reply","id":"1","method":"server.status"}"#,
            r#"[{"type":"request","id":"1","method":"server.status"}]"#,
            "not json",
        ] {
            assert!(matches!(check(text, false), Verdict::Reject(_)), "{text}");
        }
    }

    #[test]
    fn forwarded_text_is_reserialized() {
        let verdict = check(
            "{ \"type\" : \"request\", \"id\":\"1\", \"method\":\"server.status\" }",
            false,
        );
        assert_eq!(
            verdict,
            Verdict::Forward(r#"{"type":"request","id":"1","method":"server.status"}"#.to_string())
        );
    }

    #[test]
    fn denial_is_a_response_to_the_same_id() {
        assert_eq!(
            denial("a\"b", "nope"),
            r#"{"type":"response","id":"a\"b","seq":0,"error":{"code":"forbidden","message":"rex-guard: nope","status":403}}"#
        );
    }
}
