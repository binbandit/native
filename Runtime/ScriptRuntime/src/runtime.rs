//! Runs one script to its end: builds the isolate and the guest world, evaluates the script as an
//! ES module (so top-level `await` works and positions match the source the host sent), then turns
//! the event loop over tool results and timers until the script finishes, fails or is stopped.

use crate::bridge::{self, Bridge, Completion};
use crate::protocol::{Binding, Failure, FailureKind, Inbound, Outbound, emit};
use std::collections::BTreeMap;
use std::ffi::c_void;
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::mpsc::{Receiver, RecvTimeoutError};
use std::sync::{Arc, Mutex};
use std::time::Instant;

/// The name scripts' stack frames carry; the guest uses it to find positions in the script.
const SCRIPT_NAME: &str = "script.js";
const BOOTSTRAP_NAME: &str = "native:bootstrap";
/// Globals V8 provides that a script has no use for and that only widen what it can reach.
const REMOVED_GLOBALS: [&str; 4] = ["console", "WebAssembly", "SharedArrayBuffer", "Atomics"];

pub enum Input {
    Frame(Inbound),
    /// The host closed stdin: it has gone, or wants the script stopped.
    Closed,
    Invalid(String),
}

/// What the stdin reader thread and the evaluation share, so the reader can stop a script that is
/// busy in JavaScript when the host goes away.
#[derive(Default)]
pub struct Shared {
    pub isolate: Mutex<Option<v8::IsolateHandle>>,
    pub input_ended: AtomicBool,
}

impl Shared {
    pub fn stop(&self) {
        self.input_ended.store(true, Ordering::Release);
        if let Some(handle) = self.isolate.lock().unwrap_or_else(|poison| poison.into_inner()).as_ref() {
            handle.terminate_execution();
        }
    }
}

/// How the process should end once `run` returns.
pub enum Ending {
    /// A terminal frame went out, or the host left and there's no one to tell.
    Finished,
    /// The host broke the protocol; the error frame has gone out.
    ProtocolError,
}

struct HeapGuard {
    handle: v8::IsolateHandle,
    exceeded: AtomicBool,
}

/// V8 calls this just before it would run out of heap, which would otherwise abort the process.
/// Stopping the script instead lets the runtime report a memory failure.
unsafe extern "C" fn near_heap_limit(data: *mut c_void, current_limit: usize, _initial_limit: usize) -> usize {
    // SAFETY: `data` is the `HeapGuard` boxed in `run`, which outlives the isolate.
    let guard = unsafe { &*(data as *const HeapGuard) };
    guard.exceeded.store(true, Ordering::Release);
    guard.handle.terminate_execution();
    // Headroom to unwind the stack; the script never runs again.
    current_limit.saturating_mul(2)
}

pub struct Evaluation {
    pub code: String,
    pub bindings: Vec<Binding>,
    pub inputs: BTreeMap<String, String>,
}

/// The three guest functions `bootstrap.js` hands back: settle the evaluation promise, deliver a
/// tool result, fire a timer.
struct Guest {
    settle: v8::Global<v8::Function>,
    deliver: v8::Global<v8::Function>,
    fire: v8::Global<v8::Function>,
}

pub fn run(evaluation: Evaluation, input: &Receiver<Input>, shared: &Arc<Shared>, heap_limit: usize) -> Ending {
    // Declared before the isolate so it's dropped after it: the heap callback points into it.
    let guard: Box<HeapGuard>;
    let mut isolate = v8::Isolate::new(v8::CreateParams::default().heap_limits(0, heap_limit));
    guard = Box::new(HeapGuard { handle: isolate.thread_safe_handle(), exceeded: AtomicBool::new(false) });
    isolate.add_near_heap_limit_callback(near_heap_limit, &*guard as *const HeapGuard as *mut c_void);
    isolate.set_microtasks_policy(v8::MicrotasksPolicy::Explicit);
    isolate.set_slot(Bridge::new(evaluation.bindings, evaluation.inputs));
    *shared.isolate.lock().unwrap_or_else(|poison| poison.into_inner()) = Some(isolate.thread_safe_handle());
    if shared.input_ended.load(Ordering::Acquire) {
        return Ending::Finished;
    }

    let ending = {
        v8::scope!(let handle_scope, &mut isolate);
        let context = v8::Context::new(handle_scope, Default::default());
        let scope = &mut v8::ContextScope::new(handle_scope, context);
        match install_guest(scope) {
            Ok(guest) => evaluate(scope, &guest, &evaluation.code, input, shared, &guard),
            Err(failure) => finish_with(Completion::Failed(failure)),
        }
    };
    *shared.isolate.lock().unwrap_or_else(|poison| poison.into_inner()) = None;
    ending
}

fn install_guest(scope: &mut v8::PinScope) -> Result<Guest, Failure> {
    let global = scope.get_current_context().global(scope);
    for name in REMOVED_GLOBALS {
        let key = v8_string(scope, name)?;
        global.delete(scope, key.into());
    }
    let key = v8_string(scope, "__native_host")?;
    let host = v8::Function::new(scope, bridge::host_callback).ok_or_else(|| internal("Couldn't create the host bridge"))?;
    global.set(scope, key.into(), host.into());

    v8::tc_scope!(let tc, scope);
    let source = v8_string(tc, include_str!("bootstrap.js"))?;
    let name = v8_string(tc, BOOTSTRAP_NAME)?;
    let origin = v8::ScriptOrigin::new(tc, name.into(), 0, 0, false, 0, None, false, false, false, None);
    let ran = v8::Script::compile(tc, source, Some(&origin)).and_then(|script| script.run(tc));
    if ran.is_none() {
        let reason = tc.exception().map(|error| error.to_rust_string_lossy(tc)).unwrap_or_default();
        return Err(internal(&format!("The script runtime didn't start: {reason}")));
    }
    let key = v8_string(tc, "__native_guest")?;
    let exports = global.get(tc, key.into()).and_then(|value| v8::Local::<v8::Array>::try_from(value).ok());
    global.delete(tc, key.into());
    let exports = exports.ok_or_else(|| internal("The script runtime didn't start"))?;
    let function = |index| {
        exports
            .get_index(tc, index)
            .and_then(|value| v8::Local::<v8::Function>::try_from(value).ok())
            .map(|function| v8::Global::new(tc, function))
            .ok_or_else(|| internal("The script runtime didn't start"))
    };
    Ok(Guest { settle: function(0)?, deliver: function(1)?, fire: function(2)? })
}

fn evaluate(
    scope: &mut v8::PinScope,
    guest: &Guest,
    code: &str,
    input: &Receiver<Input>,
    shared: &Shared,
    guard: &HeapGuard,
) -> Ending {
    emit(&Outbound::EvaluationStarted);
    let module = match compile(scope, code) {
        Ok(module) => module,
        Err(failure) => return finish_with(Completion::Failed(failure)),
    };
    let module = v8::Local::new(scope, &module);
    let promise = {
        v8::tc_scope!(let tc, scope);
        if module.instantiate_module(tc, refuse_imports).is_none() {
            None
        } else {
            module.evaluate(tc).map(|value| v8::Global::new(tc, value))
        }
    };
    if let Some(promise) = promise {
        let promise = v8::Local::new(scope, &promise);
        call(scope, &guest.settle, &[promise]);
    }

    loop {
        scope.perform_microtask_checkpoint();
        if let Some(ending) = stopped(scope, shared, guard) {
            return ending;
        }
        let state = bridge::bridge(scope);
        match state.completion.take() {
            Some(Completion::Done) if !state.outstanding.is_empty() => {
                // Calls the script started without awaiting still run to the end.
                state.completion = Some(Completion::Done);
            }
            Some(completion) => return finish_with(completion),
            None if state.outstanding.is_empty() && state.timers.is_empty() => {
                return finish_with(Completion::Failed(stalled(scope, &module)));
            }
            None => {}
        }

        let next_timer = bridge::bridge(scope).next_timer();
        let received = match next_timer {
            Some((_, due)) => input.recv_timeout(due.saturating_duration_since(Instant::now())),
            None => input.recv().map_err(|_| RecvTimeoutError::Disconnected),
        };
        match received {
            Ok(Input::Frame(Inbound::ToolResult { id, is_error, content })) => {
                if !bridge::bridge(scope).outstanding.remove(&id) {
                    return protocol_error("The host answered a tool call that isn't in flight");
                }
                let id_value = v8::Integer::new_from_unsigned(scope, id).into();
                let is_error = v8::Boolean::new(scope, is_error).into();
                let Ok(content) = v8_string(scope, &content.to_string()) else {
                    return protocol_error("A tool result is too large");
                };
                call(scope, &guest.deliver, &[id_value, is_error, content.into()]);
            }
            Ok(Input::Frame(Inbound::Evaluate { .. })) => return protocol_error("A runtime runs one script"),
            Ok(Input::Invalid(reason)) => return protocol_error(&reason),
            Ok(Input::Closed) | Err(RecvTimeoutError::Disconnected) => return Ending::Finished,
            Err(RecvTimeoutError::Timeout) => {
                if let Some((id, _)) = next_timer {
                    if bridge::bridge(scope).take_timer(id) {
                        let id_value = v8::Integer::new_from_unsigned(scope, id).into();
                        call(scope, &guest.fire, &[id_value]);
                    }
                }
            }
        }
    }
}

/// Whether the script was stopped from outside JavaScript, and how to end if so.
fn stopped(scope: &mut v8::PinScope, shared: &Shared, guard: &HeapGuard) -> Option<Ending> {
    if shared.input_ended.load(Ordering::Acquire) {
        return Some(Ending::Finished);
    }
    if guard.exceeded.load(Ordering::Acquire) {
        let failure = Failure::new(FailureKind::Memory, "The script used more memory than its limit allows");
        return Some(finish_with(Completion::Failed(failure)));
    }
    if scope.is_execution_terminating() {
        // Only `exit()` terminates execution from inside the script.
        let completion = bridge::bridge(scope).completion.take().unwrap_or(Completion::Exited);
        return Some(finish_with(completion));
    }
    None
}

fn compile(scope: &mut v8::PinScope, code: &str) -> Result<v8::Global<v8::Module>, Failure> {
    v8::tc_scope!(let tc, scope);
    let source = v8::String::new(tc, code).ok_or_else(|| Failure::new(FailureKind::Syntax, "The script is too large"))?;
    let name = v8_string(tc, SCRIPT_NAME)?;
    let origin = v8::ScriptOrigin::new(tc, name.into(), 0, 0, false, 0, None, false, false, true, None);
    let mut source = v8::script_compiler::Source::new(source, Some(&origin));
    let Some(module) = v8::script_compiler::compile_module(tc, &mut source) else {
        let message = tc.exception().map(|error| error.to_rust_string_lossy(tc)).unwrap_or_else(|| "The script doesn't parse".into());
        let mut failure = Failure::new(FailureKind::Syntax, message);
        if let Some(message) = tc.message() {
            if let Some(line) = message.get_line_number(tc) {
                failure = failure.at(line as u32, message.get_start_column() as u32 + 1);
            }
        }
        return Err(failure);
    };
    let requests = module.get_module_requests();
    if requests.length() > 0 {
        let mut failure = Failure::new(
            FailureKind::Syntax,
            "Scripts can't import modules: there are none. Call tools.<path>() for everything outside the script.",
        );
        let request = requests.get(tc, 0).and_then(|data| v8::Local::<v8::ModuleRequest>::try_from(data).ok());
        if let Some(request) = request {
            let location = module.source_offset_to_location(request.get_source_offset());
            failure = failure.at(location.get_line_number() as u32 + 1, location.get_column_number() as u32 + 1);
        }
        return Err(failure);
    }
    Ok(v8::Global::new(tc, module))
}

/// Never called: `compile` turns away scripts that import anything before instantiation.
fn refuse_imports<'s>(
    _context: v8::Local<'s, v8::Context>,
    _specifier: v8::Local<'s, v8::String>,
    _attributes: v8::Local<'s, v8::FixedArray>,
    _referrer: v8::Local<'s, v8::Module>,
) -> Option<v8::Local<'s, v8::Module>> {
    None
}

/// The script awaits something that can't settle: no tool call or timer is left to wake it.
fn stalled(scope: &mut v8::PinScope, module: &v8::Local<v8::Module>) -> Failure {
    let failure = Failure::new(
        FailureKind::Stalled,
        "The script is waiting on a promise that nothing will settle: no tool call or timer is pending",
    );
    let stalls = module.get_stalled_top_level_await_message(scope);
    match stalls.first().and_then(|(_, message)| message.get_line_number(scope).map(|line| (line, message.get_start_column()))) {
        Some((line, column)) => failure.at(line as u32, column as u32 + 1),
        None => failure,
    }
}

/// Calls a guest function. The guest catches the script's own errors and reports them through the
/// bridge, so anything thrown here is the runtime's problem, or termination, which the loop sees.
fn call(scope: &mut v8::PinScope, function: &v8::Global<v8::Function>, args: &[v8::Local<v8::Value>]) {
    v8::tc_scope!(let tc, scope);
    let function = v8::Local::new(tc, function);
    let receiver = v8::undefined(tc).into();
    if function.call(tc, receiver, args).is_none() && !tc.is_execution_terminating() {
        let reason = tc.exception().map(|error| error.to_rust_string_lossy(tc)).unwrap_or_default();
        let failure = internal(&format!("The script runtime failed: {reason}"));
        bridge::bridge(tc).completion.get_or_insert(Completion::Failed(failure));
    }
}

fn finish_with(completion: Completion) -> Ending {
    match completion {
        Completion::Done | Completion::Exited => emit(&Outbound::Result),
        Completion::Failed(failure) => emit(&Outbound::Error { error: &failure }),
    }
    Ending::Finished
}

fn protocol_error(reason: &str) -> Ending {
    emit(&Outbound::Error { error: &internal(reason) });
    Ending::ProtocolError
}

fn internal(message: &str) -> Failure {
    Failure::new(FailureKind::Internal, message)
}

fn v8_string<'s>(scope: &mut v8::PinScope<'s, '_>, text: &str) -> Result<v8::Local<'s, v8::String>, Failure> {
    v8::String::new(scope, text).ok_or_else(|| internal("Couldn't allocate a string"))
}
