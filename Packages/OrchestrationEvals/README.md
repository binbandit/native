# Orchestration tool-use evals

Sixteen synthetic Native cases exercise model decisions about delegation and messaging.
`bad` cases capture a failure pattern to prevent; `guard` cases protect a supported behavior;
`control` cases must answer an ordinary code question without orchestration. All three kinds
are graded against desired behavior, never rewarded for reproducing a mistake.

The package is a developer tool, not an app dependency. CI discovers its Swift Testing suite
through `scripts/ci/test-packages.sh`. No live run, credential, network or running app is required.

## Offline

From this folder:

```sh
nice -n 10 swift test -j 4 --filter ToolUseEvalTests
.build/debug/native-tool-evals list
.build/debug/native-tool-evals grade /tmp/sample.trace.json
```

`swift test` also builds the executable. For a build without tests, use `nice -n 10 swift build -j 4`.
From the repository root, `python3 scripts/evals/tool-use.py` prints the default case and exits
without invoking a model. `python3 -m unittest discover -s scripts/evals -p 'test_*.py'` checks
the CLI runner offline, including its MCP stdio transport.

The trace format is separate from NativeHost's history schema:

```json
{
  "caseID": "read-referenced-task",
  "completion": "complete",
  "calls": [{
    "tool": "get_task",
    "arguments": {"task_id": "task-cache"},
    "result": {"isError": false, "structuredContent": {"reply": "Cache expiry skips empty entries."}},
    "isError": false
  }],
  "finalText": "The audit found that cache expiry skips empty entries."
}
```

Use unprefixed Native tool names; adapt provider prefixes before grading an imported trace.
Calls stay in invocation order, with their actual arguments and results. Failed attempts count
toward maximum counts and forbidden calls, but do not satisfy requirements or ordering.
Unknown tools, unsupported arguments, absent results, wrong recipients, excess workers, missing
final answers and step limits fail. Infrastructure errors and case-ID mismatches are reported
separately, never counted as passes. The grader does not authenticate externally supplied traces.

## Optional live sample

The only live transport is the developer's configured Claude Code CLI. Nothing is installed or
downloaded by this suite. It uses Haiku, low effort, no built-in tools, strict synthetic MCP config,
no skills, no session persistence and bare mode (no project/user hooks or automatic context).
Bare mode requires the developer to supply Claude Code's supported API authentication in the
environment. The runner never reads credential files or other apps' secrets. Claude Code resolves
its own provider endpoint, including a developer-configured `ANTHROPIC_BASE_URL`; this suite has
no hardcoded remote endpoint. No production Native process or store is contacted.

From the repository root, after building the package:

```sh
python3 scripts/evals/tool-use.py --live --case wait-for-reply \
  --output /tmp/native-eval-sample
```

One case runs by default, with a $0.05 CLI spend cap, 120-second wall-clock limit and 12 recorded
tool calls. `--all` runs all 16 sequentially (up to $0.80 in configured per-case caps). Treat the
CLI cap as a guard rather than an exact billing guarantee. `--budget-usd` accepts at most $0.10;
`--timeout` accepts at most 300 seconds. `--claude` and `--binary` select local executables.
Use a new empty output directory for each sample. Repeat manually for multiple samples; compare
the same model/settings and inspect traces instead of treating a small sample as a confidence bound.

Each sample saves a normalized trace and a report with requested model/effort, actual model IDs
when reported, usage, reported cost, elapsed time, outcome and failed checks. CLI authentication,
timeout, missing-server and malformed-output failures are infrastructure errors. Raw CLI stderr
and credentials are not saved or printed. Artifacts contain synthetic prompts and model output;
keep them outside the repository and delete them when done.

Network declaration: this opt-in operation sends only the synthetic case, production tool
descriptions and synthetic results through Claude Code's existing provider transport. It adds no
telemetry, update check, download, listener or background service. Before starting the CLI, it
resolves Native's existing `dev.binbandit.native` managed policy and refuses restricted deployment
modes, disabled Claude Code execution, denied `native-eval` MCP, or denied `agents.provider` /
`mcp.stdio` services. Restricted deployments are refused because this runner cannot enforce a
third-party CLI's remote origins. Offline tests and grading remain available there. Claude Code
also retains its own organization policy. Live operation is never part of CI.

## What this proves

The server constructs `OrchestrationTools.all(TaskOrchestrator(runtime: EvalRuntime(...)))`.
Names, descriptions, input/output schemas, instructions, authorization and result formatting
come from production sources. Tests execute those handlers and round-trip their wire results.
The small schema validator deliberately supports only the current input-schema vocabulary;
tests detect schema drift. No production handler, host record or orchestration rule is changed.

Only the parent model is live. Child agents are simulated, including `review-agent`, which is a
fixture plugin ID. Waiting completes immediately with a scripted reply or approval state.
Passing a case does not prove ACP execution, worker quality, isolation, filesystem safety,
delivery durability or recovery. The suite supplies seven MCP tools only; it does not test
Native's skill-discovery route or whether a shell-enabled agent would bypass the tool boundary.

The initial cases intentionally omit exact model/effort delegation, permission overrides,
isolated checkouts, cross-host history and async completion wakeups. The production tool accepts
launch options, but the synthetic runtime does not validate agent-advertised values or checkouts.
Fresh reviews are requested explicitly; continuing a reviewer uses
Native's supported `send_message`, rather than imposing another system's review convention.
Provenance and MIT notices are recorded in [the decision](../../docs/decisions/2026-11-01-tool-use-evals.md).
