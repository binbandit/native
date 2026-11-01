# Developer orchestration tool-use evals

Native needs a small behavior suite to catch tool-description and instruction regressions that
deterministic lifecycle tests cannot measure. A developer-only Swift package grades transcripts
against 16 bad/guard/control cases using the seven production orchestration tools and a synthetic
`TaskRuntime`. It has no app linkage, host schema changes, third-party dependencies or mandatory
network operation. Swift Testing checks both good traces and adversarial mutations offline.

The optional live runner uses the existing configurable Claude Code transport on Haiku at low
effort. Managed policy can deny it; restricted deployments remain offline. The full transport,
data, cost and retention declaration and commands live in
[Packages/OrchestrationEvals/README.md](../../Packages/OrchestrationEvals/README.md).

## Provenance

The source snapshot identified by the research study is
`ce9e01640636c0884c4a7574a722bf1d773cfa07`. The supplied source directory is a read-only export
without git metadata, so that identifier is study provenance, not an independently verified HEAD.
Only these files were consulted for the adaptation:

- `evals/mcp-tool-use/cases/orchestration.ndjson`: selected fresh-review, follow-up, unavailable
  agent, counts/diversity, cancellation, messaging, referenced-task and no-orchestration patterns.
- `evals/mcp-tool-use/run.ts`: required/forbidden calls, argument matching, counts, ordering and
  final-answer checks.
- `evals/mcp-tool-use/run.test.ts` and `evals/mcp-tool-use/README.md`: grader tests and simulator limits.

The adapted files are `ToolUseCases.swift`, `ToolUseCase.swift` and `ToolUseGrader.swift` under
`Packages/OrchestrationEvals/Sources/NativeToolEvals`. Each carries the full MIT copyright,
permission and warranty notice. Case prompts are newly written for Native; tool declarations are
Native's own. No upstream prompts, pass rates, tool catalog or runner implementation are imported.
No code from the source export was installed or executed.

The initial suite protects only today's public tool contract. It does not require model/options,
permission changes, worktree preparation, async wakes or cross-host transcript APIs. Those behaviors
can gain cases when their public APIs exist, without changing the host's task history schema here.
