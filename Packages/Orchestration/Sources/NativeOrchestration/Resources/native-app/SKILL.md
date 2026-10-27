---
name: native-app
description: Use Native to delegate tasks, message related agents, check task progress, diagnose setup, or read Native plugin guides.
---

Native runs coding agents side by side. Use the `native` command in this skill's `scripts/` folder.
Resolve that path from this skill's directory, not the project's working directory.
The shell's session credential identifies your task; keep it private. Commands use the same local
endpoint, task scope, permissions and organization policy as Native's MCP tools.

Run `scripts/native list_agents` to see available agents. Run `scripts/native list_tasks` to see
your children and, if you are a delegated task, your parent and siblings.

Read [references/tasks.md](references/tasks.md) when delegating or coordinating work.
Read [references/setup.md](references/setup.md) when diagnosing Native or extending it.
Read [references/scripts.md](references/scripts.md) when collecting several tool results in JavaScript.

Commands print JSON. Add `--text` for readable text. Pass a JSON argument object as one quoted
argument, or use `--stdin` to read it from standard input. A failure prints to stderr and exits nonzero.
Never pick another task's credential or bypass an approval or managed restriction. If Native is
unavailable, reopen the task in Native; do not start another host or change agent configuration.
If the shell sandbox blocks loopback access, request its normal permission for this command.
If permission is denied, stop; do not change the sandbox or managed policy.
