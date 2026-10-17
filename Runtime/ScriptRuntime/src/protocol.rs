//! The frames the runtime exchanges with its host: one JSON object per line, inbound on stdin and
//! outbound on stdout. `docs/script-runtime.md` documents the protocol; keep the two in step.

use serde::{Deserialize, Serialize};
use serde_json::Value;
use std::collections::{BTreeMap, HashSet};
use std::io::{self, BufRead, Write};

pub const PROTOCOL_VERSION: u32 = 2;

pub const MIB: usize = 1024 * 1024;
/// The longest inbound line: the script and its inputs, or one tool result.
pub const MAX_LINE: usize = 10 * MIB;
/// All the text one script can emit.
pub const MAX_OUTPUT: usize = 5 * MIB;
/// How many times one script can call `text()`.
pub const MAX_TEXT_CALLS: usize = 1024;
/// Text goes out in pieces of at most this many bytes, so an outbound frame stays well under the
/// host's line limit even when JSON escaping inflates it.
pub const TEXT_CHUNK: usize = MIB;
/// Tool calls a script can have in flight at once.
pub const MAX_OUTSTANDING_CALLS: usize = 128;
/// Timers a script can have scheduled at once.
pub const MAX_TIMERS: usize = 1024;

/// Path segments that would reach `Object.prototype` machinery if they named a tool.
const RESERVED_SEGMENTS: [&str; 3] = ["__proto__", "constructor", "prototype"];

/// Exposes the host tool `tool_name` to the script as `tools.<path>`.
#[derive(Debug, Clone, Deserialize, Serialize)]
#[serde(deny_unknown_fields, rename_all = "camelCase")]
pub struct Binding {
    pub path: Vec<String>,
    pub tool_name: String,
}

#[derive(Debug, Deserialize)]
#[serde(tag = "type", rename_all = "snake_case", deny_unknown_fields)]
pub enum Inbound {
    /// The one script this process runs.
    Evaluate {
        code: String,
        #[serde(default)]
        bindings: Vec<Binding>,
        /// Text the script reads as `inputs.<name>`, so data stays out of its source.
        #[serde(default)]
        inputs: BTreeMap<String, String>,
    },
    /// The answer to a `tool_call`.
    #[serde(rename_all = "camelCase")]
    ToolResult {
        id: u32,
        is_error: bool,
        #[serde(default)]
        content: Value,
    },
}

#[derive(Debug, Serialize)]
#[serde(tag = "type", rename_all = "snake_case")]
pub enum Outbound<'a> {
    #[serde(rename_all = "camelCase")]
    Ready { protocol_version: u32 },
    EvaluationStarted,
    /// A piece of one `text()` call; `end` marks its last piece.
    Text { text: &'a str, end: bool },
    #[serde(rename_all = "camelCase")]
    ToolCall { id: u32, tool_name: &'a str, input: &'a Value },
    /// The script finished. Nothing follows.
    Result,
    /// The script failed. Nothing follows.
    Error { error: &'a Failure },
}

/// Why a script failed, with its position in the script when there is one.
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(deny_unknown_fields)]
pub struct Failure {
    pub kind: FailureKind,
    pub message: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub line: Option<u32>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub column: Option<u32>,
}

#[derive(Debug, Clone, Copy, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "snake_case")]
pub enum FailureKind {
    /// The script doesn't parse, or imports a module.
    Syntax,
    /// The script threw, or a promise it awaited rejected (a failed tool call, for example).
    Exception,
    /// The script used more memory than its heap limit.
    Memory,
    /// The script emitted more text than it may.
    OutputLimit,
    /// The script awaits something nothing will ever settle.
    Stalled,
    /// The runtime itself failed, or the host broke the protocol.
    Internal,
}

impl Failure {
    pub fn new(kind: FailureKind, message: impl Into<String>) -> Self {
        Self { kind, message: message.into(), line: None, column: None }
    }

    pub fn at(mut self, line: u32, column: u32) -> Self {
        self.line = Some(line);
        self.column = Some(column);
        self
    }
}

impl Inbound {
    /// Checks what serde can't: bindings name distinct, safe paths, and no binding sits inside
    /// another's namespace.
    fn validate(&self) -> Result<(), &'static str> {
        let Self::Evaluate { bindings, inputs, .. } = self else {
            return Ok(());
        };
        let mut leaves = HashSet::new();
        let mut namespaces = HashSet::new();
        for binding in bindings {
            if binding.path.is_empty() || binding.tool_name.is_empty() {
                return Err("A binding needs a path and a tool name");
            }
            if binding.path.iter().any(|segment| segment.is_empty() || RESERVED_SEGMENTS.contains(&segment.as_str())) {
                return Err("A binding path segment is empty or reserved");
            }
            for depth in 1..binding.path.len() {
                namespaces.insert(&binding.path[..depth]);
            }
            if !leaves.insert(binding.path.as_slice()) {
                return Err("Two bindings share a path");
            }
        }
        if leaves.iter().any(|leaf| namespaces.contains(leaf)) {
            return Err("A binding path is also another binding's namespace");
        }
        if inputs.keys().any(String::is_empty) {
            return Err("An input name is empty");
        }
        Ok(())
    }
}

#[derive(Debug)]
pub enum ReadError {
    /// The host closed stdin.
    Closed,
    /// The host sent something that isn't a valid frame.
    Invalid(String),
}

/// Reads the next frame, refusing lines over `MAX_LINE` before buffering them whole.
pub fn read_frame(reader: &mut impl BufRead) -> Result<Inbound, ReadError> {
    let mut line = Vec::new();
    loop {
        let chunk = reader.fill_buf().map_err(|error| ReadError::Invalid(error.to_string()))?;
        if chunk.is_empty() {
            return Err(if line.is_empty() { ReadError::Closed } else { ReadError::Invalid("Truncated frame".into()) });
        }
        let (take, complete) = match chunk.iter().position(|&byte| byte == b'\n') {
            Some(index) => (index + 1, true),
            None => (chunk.len(), false),
        };
        if line.len() + take > MAX_LINE {
            return Err(ReadError::Invalid("Frame exceeds the line limit".into()));
        }
        line.extend_from_slice(&chunk[..take]);
        reader.consume(take);
        if complete {
            let frame: Inbound =
                serde_json::from_slice(&line).map_err(|error| ReadError::Invalid(format!("Invalid frame: {error}")))?;
            frame.validate().map_err(|reason| ReadError::Invalid(reason.into()))?;
            return Ok(frame);
        }
    }
}

/// Writes one frame. If the host has gone away there's no one left to tell, so the process ends.
pub fn emit(frame: &Outbound) {
    let mut out = io::stdout().lock();
    let written = serde_json::to_writer(&mut out, frame).is_ok() && out.write_all(b"\n").is_ok() && out.flush().is_ok();
    if !written {
        std::process::exit(0);
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn read(text: &str) -> Result<Inbound, ReadError> {
        read_frame(&mut io::Cursor::new(text.as_bytes()))
    }

    #[test]
    fn reads_an_evaluation() {
        let frame = read(r#"{"type":"evaluate","code":"text(1)","bindings":[{"path":["a","b"],"toolName":"t"}],"inputs":{"x":"y"}}
"#);
        assert!(matches!(frame, Ok(Inbound::Evaluate { ref bindings, .. }) if bindings.len() == 1));
    }

    #[test]
    fn rejects_unsafe_and_colliding_bindings() {
        for bindings in [
            r#"[{"path":["__proto__"],"toolName":"t"}]"#,
            r#"[{"path":[],"toolName":"t"}]"#,
            r#"[{"path":["a"],"toolName":"t"},{"path":["a"],"toolName":"u"}]"#,
            r#"[{"path":["a"],"toolName":"t"},{"path":["a","b"],"toolName":"u"}]"#,
        ] {
            let frame = read(&format!("{{\"type\":\"evaluate\",\"code\":\"\",\"bindings\":{bindings}}}\n"));
            assert!(matches!(frame, Err(ReadError::Invalid(_))), "accepted {bindings}");
        }
    }

    #[test]
    fn rejects_non_string_inputs_and_unknown_fields() {
        assert!(matches!(read("{\"type\":\"evaluate\",\"code\":\"\",\"inputs\":{\"a\":1}}\n"), Err(ReadError::Invalid(_))));
        assert!(matches!(read("{\"type\":\"evaluate\",\"code\":\"\",\"extra\":1}\n"), Err(ReadError::Invalid(_))));
    }

    #[test]
    fn distinguishes_end_of_input_from_a_truncated_frame() {
        assert!(matches!(read(""), Err(ReadError::Closed)));
        assert!(matches!(read("{\"type\":"), Err(ReadError::Invalid(_))));
    }

    #[test]
    fn refuses_lines_over_the_limit() {
        let huge = format!("{{\"type\":\"evaluate\",\"code\":\"{}\"}}\n", "x".repeat(MAX_LINE));
        assert!(matches!(read(&huge), Err(ReadError::Invalid(_))));
    }

    #[test]
    fn writes_frames_in_the_documented_shape() {
        let failure = Failure::new(FailureKind::Exception, "boom").at(3, 7);
        let json = serde_json::to_string(&Outbound::Error { error: &failure }).unwrap();
        assert_eq!(json, r#"{"type":"error","error":{"kind":"exception","message":"boom","line":3,"column":7}}"#);
        let input = serde_json::json!({});
        let json = serde_json::to_string(&Outbound::ToolCall { id: 1, tool_name: "t", input: &input }).unwrap();
        assert_eq!(json, r#"{"type":"tool_call","id":1,"toolName":"t","input":{}}"#);
    }
}
