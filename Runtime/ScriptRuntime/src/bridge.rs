//! The one door between the script and the outside world. The guest (`bootstrap.js`) calls the
//! native function `__native_host` with a JSON request; everything a script can do beyond pure
//! computation goes through here, and every limit is enforced here rather than in JavaScript the
//! script could tamper with.

use crate::protocol::{
    Binding, Failure, FailureKind, MAX_OUTPUT, MAX_OUTSTANDING_CALLS, MAX_TEXT_CALLS, MAX_TIMERS,
    MAX_TOOL_INPUT, Outbound, TEXT_CHUNK, emit,
};
use serde::Deserialize;
use serde_json::{Value, json};
use std::collections::{BTreeMap, HashSet};
use std::time::{Duration, Instant};

/// The longest a timer can be set for: a day.
const MAX_TIMER_DELAY_MS: f64 = 86_400_000.0;

pub struct Timer {
    pub due: Instant,
    pub interval: Option<Duration>,
}

/// How the script ended, as far as the script itself is concerned.
pub enum Completion {
    /// Its top-level code finished.
    Done,
    /// It called `exit()`.
    Exited,
    Failed(Failure),
}

pub struct Bridge {
    bindings: Vec<Binding>,
    inputs: BTreeMap<String, String>,
    last_id: u32,
    output_bytes: usize,
    text_calls: usize,
    /// Tool calls sent to the host and not yet answered.
    pub outstanding: HashSet<u32>,
    pub timers: BTreeMap<u32, Timer>,
    pub completion: Option<Completion>,
}

#[derive(Deserialize)]
#[serde(tag = "op", rename_all = "snake_case", deny_unknown_fields)]
enum Request {
    Metadata,
    Text { text: String },
    Call {
        index: usize,
        input: Value,
        /// Where in the script the call was made, when the guest could tell.
        #[serde(default)]
        line: Option<u32>,
        #[serde(default)]
        column: Option<u32>,
    },
    Schedule { delay: f64, repeat: bool },
    Clear { id: u32 },
    Exit,
    Complete,
    Fail { failure: Failure },
}

/// A request the bridge turned down; the guest throws it into the script as a `TypeError`.
struct Refusal {
    message: String,
    kind: Option<FailureKind>,
}

impl From<&str> for Refusal {
    fn from(message: &str) -> Self {
        Self {
            message: message.into(),
            kind: None,
        }
    }
}

impl Bridge {
    pub fn new(bindings: Vec<Binding>, inputs: BTreeMap<String, String>) -> Self {
        Self {
            bindings,
            inputs,
            last_id: 0,
            output_bytes: 0,
            text_calls: 0,
            outstanding: HashSet::new(),
            timers: BTreeMap::new(),
            completion: None,
        }
    }

    /// The earliest timer, if any is scheduled.
    pub fn next_timer(&self) -> Option<(u32, Instant)> {
        self.timers
            .iter()
            .min_by_key(|(_, timer)| timer.due)
            .map(|(id, timer)| (*id, timer.due))
    }

    /// Takes timer `id` for firing, rescheduling it if it repeats. False if it was cleared.
    pub fn take_timer(&mut self, id: u32) -> bool {
        let Some(timer) = self.timers.get_mut(&id) else {
            return false;
        };
        match timer.interval {
            Some(interval) => timer.due = Instant::now() + interval,
            None => {
                self.timers.remove(&id);
            }
        }
        true
    }

    fn next_id(&mut self) -> Result<u32, Refusal> {
        self.last_id = self
            .last_id
            .checked_add(1)
            .ok_or("The script ran out of identifiers")?;
        Ok(self.last_id)
    }

    fn handle(&mut self, request: Request) -> Result<Value, Refusal> {
        match request {
            Request::Metadata => Ok(json!({ "bindings": self.bindings, "inputs": self.inputs })),
            Request::Text { text } => {
                if self.text_calls >= MAX_TEXT_CALLS || text.len() > MAX_OUTPUT - self.output_bytes
                {
                    return Err(Refusal {
                        message: format!(
                            "Output limit reached: a script can emit {} MiB of text in {MAX_TEXT_CALLS} text() calls",
                            MAX_OUTPUT / crate::protocol::MIB
                        ),
                        kind: Some(FailureKind::OutputLimit),
                    });
                }
                self.text_calls += 1;
                self.output_bytes += text.len();
                emit_text(&text);
                Ok(Value::Null)
            }
            Request::Call {
                index,
                input,
                line,
                column,
            } => {
                let tool_name = self
                    .bindings
                    .get(index)
                    .ok_or("Unknown tool")?
                    .tool_name
                    .clone();
                if !input.is_object() {
                    return Err("Tools take one object argument".into());
                }
                if input.to_string().len() > MAX_TOOL_INPUT {
                    return Err("A tool's argument can be at most 1 MiB of JSON".into());
                }
                if self.outstanding.len() >= MAX_OUTSTANDING_CALLS {
                    return Err(format!(
                        "A script can have at most {MAX_OUTSTANDING_CALLS} tool calls in flight"
                    )
                    .as_str()
                    .into());
                }
                let id = self.next_id()?;
                self.outstanding.insert(id);
                emit(&Outbound::ToolCall {
                    id,
                    tool_name: &tool_name,
                    input: &input,
                    line,
                    column,
                });
                Ok(json!(id))
            }
            Request::Schedule { delay, repeat } => {
                // NaN and negative delays fire immediately, as in browsers.
                let delay = if delay.is_nan() { 0.0 } else { delay.max(0.0) };
                if delay > MAX_TIMER_DELAY_MS {
                    return Err("Timers can be set for at most a day".into());
                }
                if self.timers.len() >= MAX_TIMERS {
                    return Err(format!("A script can have at most {MAX_TIMERS} timers")
                        .as_str()
                        .into());
                }
                let id = self.next_id()?;
                let delay = Duration::from_millis(delay as u64);
                self.timers.insert(
                    id,
                    Timer {
                        due: Instant::now() + delay,
                        interval: repeat.then_some(delay),
                    },
                );
                Ok(json!(id))
            }
            Request::Clear { id } => {
                self.timers.remove(&id);
                Ok(Value::Null)
            }
            Request::Exit => {
                self.complete(Completion::Exited);
                Ok(Value::Null)
            }
            Request::Complete => {
                self.complete(Completion::Done);
                Ok(Value::Null)
            }
            Request::Fail { failure } => {
                self.complete(Completion::Failed(failure));
                Ok(Value::Null)
            }
        }
    }

    /// The first ending wins: a failure reported after `exit()`, for example, changes nothing.
    fn complete(&mut self, completion: Completion) {
        self.completion.get_or_insert(completion);
    }
}

fn emit_text(text: &str) {
    let mut rest = text;
    loop {
        let mut end = rest.len().min(TEXT_CHUNK);
        while !rest.is_char_boundary(end) {
            end -= 1;
        }
        let (piece, tail) = rest.split_at(end);
        emit(&Outbound::Text {
            text: piece,
            end: tail.is_empty(),
        });
        if tail.is_empty() {
            return;
        }
        rest = tail;
    }
}

/// `__native_host(requestJSON) -> replyJSON`. The reply is `{"value": …}`, or `{"error": message}`
/// with an optional failure `kind` for the guest to throw.
pub fn host_callback(
    scope: &mut v8::PinScope,
    args: v8::FunctionCallbackArguments,
    mut rv: v8::ReturnValue,
) {
    let argument = args.get(0);
    let reply = if argument.is_string() {
        let text = argument.to_rust_string_lossy(scope);
        match serde_json::from_str::<Request>(&text) {
            Ok(request) => bridge(scope).handle(request),
            Err(_) => Err("Invalid bridge request".into()),
        }
    } else {
        Err("Invalid bridge request".into())
    };
    if matches!(bridge(scope).completion, Some(Completion::Exited)) {
        // `exit()` stops the script where it stands.
        scope.terminate_execution();
        return;
    }
    let reply = match reply {
        Ok(value) => json!({ "value": value }),
        Err(refusal) => json!({ "error": refusal.message, "kind": refusal.kind }),
    };
    if let Some(text) = v8::String::new(scope, &reply.to_string()) {
        rv.set(text.into());
    }
}

/// The isolate always carries its bridge; `runtime::run` puts it there before any script runs.
pub fn bridge<'a>(scope: &'a mut v8::PinScope) -> &'a mut Bridge {
    scope
        .get_slot_mut::<Bridge>()
        .expect("the isolate has a bridge")
}
