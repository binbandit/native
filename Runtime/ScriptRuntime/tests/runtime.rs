//! Drives the built runtime over its line protocol, the way a host does.

use serde_json::{Value, json};
use std::io::{BufRead, BufReader, Write};
use std::process::{Child, ChildStdin, Command, Stdio};
use std::sync::mpsc;
use std::time::Duration;

const TIMEOUT: Duration = Duration::from_secs(20);

struct Runtime {
    child: Child,
    stdin: Option<ChildStdin>,
    frames: mpsc::Receiver<Value>,
}

impl Runtime {
    fn start(arguments: &[&str]) -> Self {
        let mut child = Command::new(env!("CARGO_BIN_EXE_native-script-runtime"))
            .args(arguments)
            .stdin(Stdio::piped())
            .stdout(Stdio::piped())
            .spawn()
            .expect("the runtime starts");
        let stdout = BufReader::new(child.stdout.take().unwrap());
        let (sender, frames) = mpsc::channel();
        std::thread::spawn(move || {
            for line in stdout.lines().map_while(Result::ok) {
                if sender
                    .send(serde_json::from_str(&line).expect("frames are JSON"))
                    .is_err()
                {
                    return;
                }
            }
        });
        let stdin = child.stdin.take();
        let mut runtime = Self {
            child,
            stdin,
            frames,
        };
        assert_eq!(runtime.next()["type"], "ready");
        runtime
    }

    fn send(&mut self, frame: Value) {
        let stdin = self.stdin.as_mut().unwrap();
        writeln!(stdin, "{frame}").unwrap();
        stdin.flush().unwrap();
    }

    fn next(&mut self) -> Value {
        self.frames
            .recv_timeout(TIMEOUT)
            .expect("a frame arrives in time")
    }
}

impl Drop for Runtime {
    fn drop(&mut self) {
        let _ = self.child.kill();
        let _ = self.child.wait();
    }
}

/// What a run produced: its text, the tool calls it made, and its terminal frame.
struct Run {
    text: Vec<String>,
    calls: Vec<(String, Value)>,
    end: Value,
}

impl Run {
    fn error(&self) -> &Value {
        assert_eq!(
            self.end["type"], "error",
            "expected a failure, got {}",
            self.end
        );
        &self.end["error"]
    }
}

fn run_with(
    code: &str,
    bindings: Value,
    inputs: Value,
    arguments: &[&str],
    tool: impl Fn(&str, &Value) -> (bool, Value),
) -> Run {
    let mut runtime = Runtime::start(arguments);
    runtime
        .send(json!({ "type": "evaluate", "code": code, "bindings": bindings, "inputs": inputs }));
    assert_eq!(runtime.next()["type"], "evaluation_started");
    let mut run = Run {
        text: vec![],
        calls: vec![],
        end: Value::Null,
    };
    let mut pending = String::new();
    loop {
        let frame = runtime.next();
        match frame["type"].as_str().unwrap() {
            "text" => {
                pending.push_str(frame["text"].as_str().unwrap());
                if frame["end"] == true {
                    run.text.push(std::mem::take(&mut pending));
                }
            }
            "tool_call" => {
                let name = frame["toolName"].as_str().unwrap().to_owned();
                let (is_error, content) = tool(&name, &frame["input"]);
                run.calls.push((name, frame["input"].clone()));
                runtime.send(json!({ "type": "tool_result", "id": frame["id"], "isError": is_error, "content": content }));
            }
            "result" | "error" => {
                run.end = frame;
                return run;
            }
            other => panic!("unexpected frame {other}"),
        }
    }
}

fn run(code: &str) -> Run {
    run_with(code, json!([]), json!({}), &[], |_, _| {
        (true, json!("no tools"))
    })
}

fn tasks() -> Value {
    json!([
        { "path": ["tasks", "list"], "toolName": "list_tasks" },
        { "path": ["tasks", "get"], "toolName": "get_task" },
    ])
}

fn task_tool(name: &str, input: &Value) -> (bool, Value) {
    match name {
        "list_tasks" => (false, json!({ "tasks": [{ "id": "t1" }, { "id": "t2" }] })),
        "get_task" if input["task_id"] == "missing" => (true, json!("There's no task \"missing\"")),
        "get_task" => (
            false,
            json!({ "task_id": input["task_id"], "status": "idle" }),
        ),
        _ => (true, json!("unknown tool")),
    }
}

#[test]
fn calls_bound_tools_and_prints_a_summary() {
    let run = run_with(
        r#"
        const { tasks } = await tools.tasks.list();
        const details = await Promise.all(tasks.map((task) => tools.tasks.get({ task_id: task.id })));
        text(`${details.length} tasks:`, details.map((task) => `${task.task_id} ${task.status}`).join(", "));
        console.log({ done: true });
        "#,
        tasks(),
        json!({}),
        &[],
        task_tool,
    );
    assert_eq!(run.end["type"], "result");
    assert_eq!(run.text, ["2 tasks: t1 idle, t2 idle", r#"{"done":true}"#]);
    assert_eq!(run.calls.len(), 3);
    assert_eq!(
        run.calls[1],
        ("get_task".to_owned(), json!({ "task_id": "t1" }))
    );
}

#[test]
fn reports_syntax_errors_with_their_position() {
    let error = run("const a = 1;\nconst b = ;\n").error().clone();
    assert_eq!(error["kind"], "syntax");
    assert_eq!(
        (error["line"].clone(), error["column"].clone()),
        (json!(2), json!(11))
    );
}

#[test]
fn reports_exceptions_with_their_position() {
    let error = run("text('before');\n  null.boom;\n").error().clone();
    assert_eq!(error["kind"], "exception");
    assert!(error["message"].as_str().unwrap().starts_with("TypeError"));
    assert_eq!(
        (error["line"].clone(), error["column"].clone()),
        (json!(2), json!(8))
    );
}

#[test]
fn a_failed_tool_call_rejects_at_its_call_site() {
    let code = "try { await tools.tasks.get({ task_id: 'missing' }) } catch (error) { text(error.message) }\n\
                await tools.tasks.get({ task_id: 'missing' });\n";
    let run = run_with(code, tasks(), json!({}), &[], task_tool);
    assert_eq!(
        run.text,
        [r#"tools.tasks.get failed: There's no task "missing""#]
    );
    let error = run.error();
    assert_eq!(error["kind"], "exception");
    assert_eq!(error["line"], 2);
}

#[test]
fn scripts_cannot_reach_modules_files_network_or_processes() {
    let probes = r#"
        const checks = {
          require: () => require("fs"),
          process: () => process.env,
          fetch: () => fetch("https://example.com"),
          XMLHttpRequest: () => new XMLHttpRequest(),
          WebAssembly: () => WebAssembly.Module,
          SharedArrayBuffer: () => new SharedArrayBuffer(8),
          Atomics: () => Atomics.wait,
          Deno: () => Deno.readTextFile("/etc/hosts"),
          Bun: () => Bun.file("/etc/hosts"),
          host: () => __native_host("{}"),
          guest: () => __native_guest,
        };
        for (const [name, probe] of Object.entries(checks)) {
          try { probe(); text(`${name}: ESCAPED`) } catch (error) { text(`${name}: ${error.name}`) }
        }
        try { await import("node:fs"); text("import(): ESCAPED") } catch (error) { text(`import(): ${error.name}`) }
        text(typeof globalThis.require, Object.keys(globalThis).sort().join(","));
    "#;
    let probed = run(probes);
    assert_eq!(probed.end["type"], "result");
    assert!(
        probed.text.iter().all(|line| !line.contains("ESCAPED")),
        "{:?}",
        probed.text
    );
    assert_eq!(
        probed.text.last().unwrap(),
        "function clearInterval,clearTimeout,console,exit,inputs,setInterval,setTimeout,text,tools"
    );

    let error = run("text('never');\nimport fs from 'node:fs';\n")
        .error()
        .clone();
    assert_eq!(
        (error["kind"].clone(), error["line"].clone()),
        (json!("syntax"), json!(2))
    );
}

#[test]
fn inputs_carry_text_and_name_what_is_missing() {
    let code = "text(inputs.greeting.toUpperCase()); inputs.other";
    let run = run_with(code, json!([]), json!({ "greeting": "hi" }), &[], task_tool);
    assert_eq!(run.text, ["HI"]);
    assert!(
        run.error()["message"]
            .as_str()
            .unwrap()
            .contains("inputs.other wasn't supplied. Inputs for this run: greeting")
    );
}

#[test]
fn unknown_tools_list_what_exists() {
    let run = run_with(
        "await tools.tasks.cancel({})",
        tasks(),
        json!({}),
        &[],
        task_tool,
    );
    assert!(
        run.error()["message"]
            .as_str()
            .unwrap()
            .contains("tools.tasks.cancel doesn't exist. Available here: list, get")
    );
}

#[test]
fn timers_fire_in_order_and_intervals_can_stop() {
    let code = r#"
        setTimeout(() => text("late"), 30);
        setTimeout(() => text("early"), 0);
        let ticks = 0;
        await new Promise((resolve) => {
          const id = setInterval(() => { ticks += 1; if (ticks === 3) { clearInterval(id); resolve(); } }, 5);
        });
        await new Promise((resolve) => setTimeout(resolve, 50));
        text("ticks", ticks);
    "#;
    assert_eq!(run(code).text, ["early", "late", "ticks 3"]);
}

#[test]
fn exit_stops_the_script_where_it_stands() {
    let exited = run("text('one'); exit(); text('two');");
    assert_eq!(exited.end["type"], "result");
    assert_eq!(exited.text, ["one"]);
}

#[test]
fn a_script_waiting_on_nothing_is_reported_as_stalled() {
    let error = run("text('waiting');\nawait new Promise(() => {});\n")
        .error()
        .clone();
    assert_eq!(error["kind"], "stalled");
    assert_eq!(error["line"], 2);
}

#[test]
fn unawaited_tool_calls_finish_before_the_result() {
    let run = run_with(
        "tools.tasks.list(); text('started')",
        tasks(),
        json!({}),
        &[],
        task_tool,
    );
    assert_eq!(run.end["type"], "result");
    assert_eq!(run.calls.len(), 1);
}

#[test]
fn output_is_limited() {
    let error =
        run("const chunk = 'x'.repeat(1024 * 1024); for (let i = 0; i < 6; i++) text(chunk);")
            .error()
            .clone();
    assert_eq!(error["kind"], "output_limit");
    let error = run("for (let i = 0; i < 2000; i++) text(i);")
        .error()
        .clone();
    assert_eq!(error["kind"], "output_limit");
}

#[test]
fn large_text_arrives_in_pieces_and_whole() {
    let large = run("text('é'.repeat(700000))");
    assert_eq!(large.text, ["é".repeat(700_000)]);
}

#[test]
fn memory_is_limited() {
    let code = "const hoard = []; while (true) hoard.push('x'.repeat(1024) + hoard.length);";
    let run = run_with(
        code,
        json!([]),
        json!({}),
        &["--max-heap-mib", "32"],
        task_tool,
    );
    assert_eq!(run.error()["kind"], "memory");
}

#[test]
fn closing_stdin_stops_a_busy_script() {
    let mut runtime = Runtime::start(&[]);
    runtime.send(json!({ "type": "evaluate", "code": "while (true) {}" }));
    assert_eq!(runtime.next()["type"], "evaluation_started");
    drop(runtime.stdin.take());
    for _ in 0..100 {
        if let Ok(Some(_)) = runtime.child.try_wait() {
            return;
        }
        std::thread::sleep(Duration::from_millis(50));
    }
    panic!("the runtime kept running after its host left");
}

#[test]
fn rejects_a_tool_result_for_a_call_that_isnt_in_flight() {
    let mut runtime = Runtime::start(&[]);
    runtime.send(json!({ "type": "evaluate", "code": "await new Promise((resolve) => setTimeout(resolve, 5000))" }));
    assert_eq!(runtime.next()["type"], "evaluation_started");
    runtime.send(json!({ "type": "tool_result", "id": 9, "isError": false, "content": null }));
    let end = runtime.next();
    assert_eq!(end["error"]["kind"], "internal");
    assert_eq!(runtime.child.wait().unwrap().code(), Some(1));
}

#[test]
fn tool_arguments_are_limited() {
    let code = "try { await tools.tasks.get({ task_id: 'x'.repeat(2 * 1024 * 1024) }) } catch (error) { text(error.message) }";
    let run = run_with(code, tasks(), json!({}), &[], task_tool);
    assert_eq!(run.text, ["A tool's argument can be at most 1 MiB of JSON"]);
    assert!(run.calls.is_empty());
}
