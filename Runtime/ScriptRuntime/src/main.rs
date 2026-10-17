//! `native-script-runtime`: runs one script in a V8 isolate for Native and exits. The script can
//! compute, print with `text()` and call the tools its host binds; it has no modules, files,
//! network or processes. The host speaks the line protocol in `protocol.rs` on stdin and stdout.
//!
//! Usage: `native-script-runtime [--max-heap-mib N]`, or `--probe-sandbox <path>` to report what the
//! process itself is allowed to do.

mod bridge;
mod probe;
mod protocol;
mod runtime;

use protocol::{Failure, FailureKind, Inbound, Outbound, ReadError, emit, read_frame};
use runtime::{Ending, Evaluation, Input, Shared};
use std::io;
use std::sync::Arc;
use std::sync::mpsc;

const DEFAULT_HEAP_MIB: usize = 128;
const MAX_HEAP_MIB: usize = 4096;

/// Interpreter only: no JIT means no writable-executable memory and a smaller attack surface, and
/// tool-calling glue doesn't need the speed. One thread keeps each script's footprint small.
const V8_FLAGS: &str = "--jitless --single-threaded";

enum Mode {
    Run { heap_mib: usize },
    Probe { path: String },
}

fn parse_arguments() -> Result<Mode, String> {
    let mut arguments = std::env::args().skip(1);
    let mut mode = Mode::Run {
        heap_mib: DEFAULT_HEAP_MIB,
    };
    while let Some(argument) = arguments.next() {
        match argument.as_str() {
            "--max-heap-mib" => {
                let value = arguments
                    .next()
                    .and_then(|value| value.parse::<usize>().ok());
                match value {
                    Some(heap_mib @ 16..=MAX_HEAP_MIB) => mode = Mode::Run { heap_mib },
                    _ => {
                        return Err(format!(
                            "--max-heap-mib takes a number from 16 to {MAX_HEAP_MIB}"
                        ));
                    }
                }
            }
            "--probe-sandbox" => {
                let path = arguments.next().ok_or("--probe-sandbox takes a path")?;
                mode = Mode::Probe { path };
            }
            other => return Err(format!("Unknown argument {other}")),
        }
    }
    Ok(mode)
}

#[cfg(feature = "sandbox")]
unsafe extern "C" {
    // The same check rusty_v8 itself uses; the dependency version is pinned.
    fn v8__V8__IsSandboxEnabled() -> bool;
}

fn main() {
    let heap_mib = match parse_arguments() {
        Ok(Mode::Run { heap_mib }) => heap_mib,
        Ok(Mode::Probe { path }) => return probe::run(&path),
        Err(message) => {
            eprintln!("{message}");
            std::process::exit(2);
        }
    };

    v8::V8::set_flags_from_string(V8_FLAGS);
    v8::V8::initialize_platform(v8::new_single_threaded_default_platform(false).make_shared());
    v8::V8::initialize();
    #[cfg(feature = "sandbox")]
    if !unsafe { v8__V8__IsSandboxEnabled() } {
        emit(&Outbound::Error {
            error: &Failure::new(
                FailureKind::Internal,
                "This runtime requires V8's memory sandbox",
            ),
        });
        std::process::exit(1);
    }

    let shared = Arc::new(Shared::default());
    let (sender, receiver) = mpsc::channel();
    let reader_shared = shared.clone();
    std::thread::spawn(move || {
        let mut stdin = io::stdin().lock();
        loop {
            let input = match read_frame(&mut stdin) {
                Ok(frame) => Input::Frame(frame),
                Err(ReadError::Closed) => Input::Closed,
                Err(ReadError::Invalid(reason)) => Input::Invalid(reason),
            };
            let last = !matches!(input, Input::Frame(_));
            if matches!(input, Input::Closed) {
                // A script busy in JavaScript wouldn't otherwise notice its host is gone.
                reader_shared.stop();
            }
            if sender.send(input).is_err() || last {
                return;
            }
        }
    });

    emit(&Outbound::Ready {
        protocol_version: protocol::PROTOCOL_VERSION,
    });
    let evaluation = match receiver.recv() {
        Ok(Input::Frame(Inbound::Evaluate {
            code,
            bindings,
            inputs,
        })) => Evaluation {
            code,
            bindings,
            inputs,
        },
        Ok(Input::Closed) | Err(_) => return,
        Ok(Input::Frame(Inbound::ToolResult { .. })) => fail("Expected a script to evaluate"),
        Ok(Input::Invalid(reason)) => fail(&reason),
    };
    match runtime::run(evaluation, &receiver, &shared, heap_mib * protocol::MIB) {
        Ending::Finished => {}
        Ending::ProtocolError => std::process::exit(1),
    }
}

fn fail(reason: &str) -> ! {
    emit(&Outbound::Error {
        error: &Failure::new(FailureKind::Internal, reason),
    });
    std::process::exit(1)
}
