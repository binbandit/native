# Script runtime

Native can run untrusted JavaScript: a script an agent wrote, and later code plugins and scripted
workflow steps. Scripts run in `native-script-runtime`, a V8 isolate in its own sandboxed process.
A script can compute, print, and call the tools its host binds for that run, and nothing else: no
modules, files, network, processes or environment. Every effect goes through a bound tool, so the
host decides exactly what a script can do.

Scripts run only on a host (`docs/architecture.md`, "Clients and hosts"). A client such as the iPad
asks its host to run one; iOS wouldn't allow V8's JIT anyway, and the runtime runs without it.

| Path | What lives there |
| --- | --- |
| `Runtime/ScriptRuntime/` | The runtime: a Rust crate on the `v8` crate (rusty_v8), its entitlements and Info.plist, tests |
| `Packages/ScriptRuntime/` | Swift: launches the runtime, speaks its protocol, runs bound tools (`ScriptRunner`) |
| `scripts/build-script-runtime.sh` | Builds and signs the runtime; the Xcode phase "Embed Script Runtime" runs it |

The runtime is built for Native: its own guest JavaScript (no bundled third-party code), a small
protocol (below), and tight boundaries.

## Security boundaries

From the inside out:

1. **The isolate.** The script's global scope is plain ECMAScript plus `tools`, `inputs`, `text`,
   `console`, timers and `exit`. There is no `require`, `import`, `process`, `fetch`, `Deno`, `Bun`,
   `WebAssembly`, `SharedArrayBuffer` or `Atomics`. Scripts compile as ES modules; any `import`
   is a syntax error and dynamic `import()` rejects. The host bridge is a single native function
   the guest captures and deletes from the global scope before the script runs; every request
   through it is checked in Rust, not in JavaScript the script could tamper with.
2. **No JIT.** V8 runs with `--jitless --single-threaded`: no writable-executable memory, a much
   smaller attack surface, and one thread per script. Tool-calling glue doesn't need the speed.
3. **V8's memory sandbox** (optional). `scripts/build-script-runtime.sh --sandbox` links V8 built
   from source with `v8_enable_sandbox`, which confines heap corruption to a reserved region. The
   runtime refuses to start if the sandbox isn't active. rusty_v8 publishes no prebuilt library
   with it, so the default build uses the pointer-compression prebuilt and doesn't have it; see
   "Building" for the cost. Both builds pass the same tests.
4. **The App Sandbox.** The runtime is signed with its own entitlements
   (`Runtime/ScriptRuntime/ScriptRuntime.entitlements`): the App Sandbox with nothing granted, so
   no network and no files outside its container, plus the hardened runtime. It needs nothing
   else: stdin and stdout are the only way in or out. Even code that escapes V8 has no more access
   than that. The App Sandbox needs a bundle identifier for a command-line tool, so `build.rs`
   links `Info.plist` into the binary (`dev.native.script-runtime`, which is also the signing
   identifier and the container name).
5. **The host.** `ScriptRunner` won't launch a runtime whose signature is invalid or lacks the
   sandbox entitlement. It starts the runtime with an empty environment and no stderr, so nothing
   of the app's leaks in; dispatches only tool calls for the bindings it was given; validates every
   frame and caps line length and output; and kills the process (SIGKILL) when the run's time is up,
   when it's cancelled, or as soon as the script ends.

A compromised runtime can therefore do at most what its bound tools allow. That's why bindings
must be things the script's caller may already do (see "Code mode").

Verify the sandbox on a build:

```sh
codesign -d --entitlements - Native.app/Contents/Helpers/native-script-runtime   # app-sandbox: true
Native.app/Contents/Helpers/native-script-runtime --probe-sandbox ~/some-file     # {"fileRead":"denied","network":"denied"}
```

`--probe-sandbox` reports what the process itself may do; the Swift tests run it against a file in
`~/Library/Caches` and expect both denied.

### Limits

| Limit | Value | Enforced by |
| --- | --- | --- |
| Wall-clock time | `ScriptLimits.time`, 60 s by default, counted from `evaluation_started`; the runtime has 15 s to get there | Host: SIGKILL |
| Heap | `ScriptLimits.heapMiB`, 128 MiB by default (`--max-heap-mib`, 16 to 4096) | Runtime: a near-heap-limit callback stops the script and reports `memory` instead of aborting |
| Tool calls per run | `ScriptLimits.toolCalls`, 1000 | Host |
| Tool result size | `ScriptLimits.toolResultBytes`, 5 MiB of JSON; larger results fail the call | Host |
| Tool calls in flight | 128 | Runtime |
| One tool argument | 1 MiB of JSON | Runtime |
| Output | 5 MiB of text in at most 1024 `text()` calls | Runtime (host stops past 6 MiB) |
| Timers | 1024 scheduled, at most a day each | Runtime |
| Inbound line | 10 MiB (script plus inputs, or one tool result) | Runtime |
| Outbound line | 8 MiB | Host |

## Writing scripts

```js
const { tasks } = await tools.list_tasks();
const details = await Promise.all(tasks.map((task) => tools.get_task({ task_id: task.id })));
text(details.filter((task) => task.status === "needs_approval").map((task) => task.task_id).join(", "));
```

- The code is an ES module body: top-level `await` works; the completion value isn't returned.
- `text(...values)` and `console.log/info/warn/error/debug` print one entry each; strings print as
  is, other values as JSON.
- `tools.<path>(input)` takes one object (or nothing) and resolves with the tool's result. A failed
  call rejects with `Error("tools.<path> failed: <message>")`, positioned at the call site. Asking
  for a tool that doesn't exist throws and lists what does.
- `inputs.<name>` reads text the host passed alongside the script, so data stays out of source.
- `setTimeout`, `setInterval`, `clearTimeout`, `clearInterval`, and `exit()` to stop at once.
- A run ends when the top-level code finishes and every tool call it started has been answered.
  Pending timers are dropped. A script awaiting something nothing can settle fails as `stalled`.

Failures carry a kind (`syntax`, `exception`, `memory`, `output_limit`, `stalled`, and host-side
`timed_out`, `tool_call_limit`, `runtime`) and, where known, the 1-based line and column in the
script as written.

## Protocol

Newline-delimited JSON on the runtime's stdin and stdout; one script per process.

```
runtime → {"type":"ready","protocolVersion":2}
host    → {"type":"evaluate","code":"…","bindings":[{"path":["tasks","get"],"toolName":"get_task"}],"inputs":{"name":"text"}}
runtime → {"type":"evaluation_started"}
runtime → {"type":"tool_call","id":1,"toolName":"get_task","input":{"task_id":"t1"},"line":2,"column":15}
host    → {"type":"tool_result","id":1,"isError":false,"content":{…}}
runtime → {"type":"text","text":"…","end":true}
runtime → {"type":"result"}                                   (or)
runtime → {"type":"error","error":{"kind":"exception","message":"TypeError: …","line":3,"column":9}}
```

`tool_call.line` and `column` say where in the script the call was made, when the runtime can
tell; they're optional, so hosts that ignore them keep working. Tools receive them as a
`ScriptCallSite` (`ScriptTool.call(_:at:)`, or `ScriptBinding(siteHandler:)`), for showing where a
call came from, such as on an approval card.

After `result` or `error` the runtime exits. Closing stdin stops the script, even one spinning in
JavaScript. A host that breaks the protocol gets an `internal` error and exit status 1.

Changes from the protocol the runtime started with (version 1):

- `protocolVersion` is 2.
- Tool calls are numbered `id`s (`tool_call.id`, `tool_result.id`) instead of `toolUseId` strings
  with a random prefix: one process runs one script, so a counter is unique.
- Text is `{"type":"text","text","end"}`: pieces of one `text()` call arrive in order and `end`
  marks the last. It replaces `content` frames grouped by `textCallId`.
- `error.kind` replaces `error.origin`, and `line`/`column` sit on the error rather than in a
  `position` object.
- `tool_result.content` is always present (null when there's nothing).
- Removed: `mission` (evaluate and the `mission` global), `image`, `notify`, `flush_output`, the
  `exit` frame (`exit()` now ends with `result`), and Task reservations. They were features of
  another product; Native can add its own when it needs them.
- The runtime exits after the terminal frame instead of waiting for the host to close stdin.
- `evaluate.inputs` must be strings (as before), and bindings are checked for collisions in Rust.

## Swift API

```swift
import ScriptRuntime

let runner = try ScriptRunner.embedded()            // nil when this build has no runtime
let result = try await runner?.run(
    code,
    bindings: [
        ScriptBinding(path: ["git", "status"], summary: "…", inputSchema: …) { input in … },  // or tool: some ScriptTool
    ],
    inputs: ["patch": patchText],
    limits: ScriptLimits(time: .seconds(30)))
result.output       // [String], one per text() call
result.toolCalls    // [ScriptToolCall]: path, input, isError, duration
result.failure      // ScriptFailure?: kind, message, line, column
result.report       // text for a model: output, then the failure
result.summary      // ScriptJSON: { output, tool_calls, failure? }
```

`ScriptTool` is `func call(_ input: ScriptJSON) async throws -> ScriptJSON`; throwing fails the
script's call with the error's description. `ScriptJSON` converts to and from other JSON types
through `init(encoding:)` and `decode(_:)`. `ScriptReference.declarations(for:)` renders bindings
as TypeScript-style signatures for a model. `run` throws only when the runtime can't start, and
`CancellationError` when cancelled; a failing script is a result with a `failure`.

The wire types, bindings and results build for iOS; `ScriptRunner` is macOS only.

## Building

```sh
scripts/build-script-runtime.sh            # build and sign into ~/Library/Caches/Native/ScriptRuntime
scripts/build-script-runtime.sh --test     # the crate's tests (cargo test --release)
(cd Packages/ScriptRuntime && swift test)  # Swift tests; the real-runtime ones skip until it's built
scripts/build-script-runtime.sh --sandbox  # with V8's memory sandbox
```

- Requires Rust (rustup or Homebrew). arm64 only, which is every Mac macOS 27 runs on.
- The first build downloads V8's prebuilt static library (37 MiB) and compiles about 100 crates:
  about 30 seconds on an M-series Mac with a fast connection. After that a build takes a few
  seconds, and an unchanged one about one. The cargo target directory is shared at
  `~/Library/Caches/Native/ScriptRuntime` (about 1 GiB; override with `NATIVE_SCRIPT_RUNTIME_CACHE`):
  Xcode's script sandbox forbids writing into the source tree, and every checkout and DerivedData
  folder can share one V8 download. Cargo's lock serializes concurrent builds.
- In Xcode, "Embed Script Runtime" runs only when a file in `Runtime/ScriptRuntime/Sources.xcfilelist`
  or the build script changes (add new source files to that list), copies the runtime to
  `Contents/Helpers/native-script-runtime` and signs it with the app's identity and its own
  entitlements before Xcode signs the app. Without cargo, or if the build fails, it prints a
  warning, leaves the runtime out, and scripts are unavailable in that build; the app still builds.
- `--sandbox` needs V8 compiled from source: about an hour and 5 GiB of disk once, by
  `Runtime/ScriptRuntime/scripts/build-v8-sandbox.py` (every input pinned by hash). Point
  `NATIVE_V8_SANDBOX_DIR` at the `gn_out` directory of an earlier sandbox build to skip that. It
  builds in its own target directory so the two variants don't overwrite each other's V8.
- Startup costs about 17 ms per script (31 ms with the V8 sandbox), measured from spawn to result.

## Code mode: `run_script`

Every agent session gets Native's own MCP server (`native/Orchestration/`). `run_script` lets an
agent send a script instead of making one tool call per step: the script calls the read-only
orchestration tools (`list_agents`, `list_tasks`, `get_task`, `wait_for_task`) as `tools.<name>()`
and returns only what it prints. Checking ten tasks or waiting on several at once becomes one call
and a few lines of result instead of a dozen round trips through the model, each paying for the
full results in context.

- Bindings are named after the MCP tools and take the same arguments, and the tool's description
  includes `ScriptReference` declarations generated from their schemas, so the model writes calls
  it already understands.
- Only read-only orchestration tools are bound. Mutating ones (`start_task`, `send_message`,
  `cancel_task`) could go through the same approval as scripted MCP servers' tools (below); until
  that's wanted, they stay out.
- `timeout_seconds` (default 60, at most 240) bounds a run below the point where MCP clients give up.
- The tool exists only when the app has a sandboxed runtime; without one Native doesn't offer it.

### Scripted MCP servers

A server like `rea` costs about 197k tokens of Claude's context per session just to list its
tools. In Settings ▸ MCP Servers, a server's ⋯ menu sets how agents reach it: loaded into each
session, or through Native's scripts. Scripted, agents don't load it at all (the same per-session
override as switching it off, `docs/agent-session-overrides.md`); Native keeps one connection to it
(`MCPSession` in `Packages/MCPClient`, opened on a script's first use) and binds its tools into
`run_script` as `tools.<server>.<tool>`. The pieces:

- Other features bind tools through `OrchestrationScriptBindings`, asked per run with the calling
  session (`OrchestrationCaller.cwd`, so switches apply per project). run_script's listing
  (`MCPTool.listing`) names what each session can reach, without a hundred declarations:
  `tools.search({ query })` resolves with the matching declarations instead.
- Read-only tools just run. A call to any other tool is approved the way the agent's own calls are,
  following the calling session's mode: a session that runs tool calls unasked (Claude Code's auto,
  bypass or don't-ask; Codex's auto review or full access, per `approvesToolCallsUnasked(inMode:)`)
  doesn't ask, and neither does a tool the user chose "Always Allow" for. Otherwise Native raises
  its own approval card in that session, one at a time, showing the tool, its arguments and the
  script line: Allow Once, Allow for This Script (the run's remaining calls), Always Allow <tool>
  (recorded per server and tool; the ⋯ menu takes it back), or Reject, which fails just that call
  with a reason the script can catch.
- A card still open when the run nears its time limit is withdrawn and the call fails, saying the
  approval is still pending, so the agent hears back before its MCP client gives up.
- Every call shows in the transcript as a quiet line under the run_script row
  ("rea · list_functions"), marked by `_meta.native.script` on a tool call Native adds itself.
- run_script is annotated read-only for a session only while everything bound for it is.

## Next uses

- **Sandboxed code plugins.** Today plugins are built in or declarative (`plugin.json`). A code
  plugin would ship JavaScript that Native runs in this runtime, with the extension points it
  declares bound as tools: a title provider gets `tools.session.firstPrompt()` and returns a title;
  a session hook gets read access to the session and can call `tools.notify()`. The manifest names
  the tools a plugin wants and the user grants them once, so a plugin can't reach past them. A
  long-lived plugin would keep one runtime per plugin instead of one per call, which needs a
  protocol extension for multiple evaluations or event delivery.
- **Scripted workflow steps.** A workflow step can be a script whose tools are the workflow's
  context: the previous step's output as `inputs`, `tools.git.diff()`, `tools.tasks.start(…)` for
  steps the workflow is allowed to take. It replaces glue that would otherwise need its own
  executable, and its output and failures (with line numbers) show in the step inspector.
- **Clients.** Both run on the host that owns the project; a client asks that host through the host
  protocol, and results come back as data.

## Decision: a Rust and V8 runtime

V8 through the `v8` crate (rusty_v8, Deno's bindings, pinned at 150.4.0) plus `serde`/`serde_json`
is the runtime's whole dependency list. JavaScriptCore would avoid the dependency, but its public API
has no heap limit and no way to stop a running script from another thread, and running it
in-process would put untrusted code inside the app; out of process it has no advantage over V8,
which also has a memory sandbox to opt into. The runtime is a separate executable, so the app takes on no Rust or C++ at
link time, and a build machine without Rust only loses scripts.
