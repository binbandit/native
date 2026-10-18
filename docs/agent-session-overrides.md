# Agent session overrides

Native can leave things out of the sessions it starts (an MCP server switched off in Settings ▸ MCP
Servers, later skills) without editing any agent's files. Features state intent as a
`SessionPolicy` (`native/Plugins/SessionPolicy.swift`); each agent's plugin translates it with a
`SessionPolicyTranslator`. Changes apply at the next session start, or when the agent restarts for
the ones applied at launch; a running turn is never interrupted.

| Agent | Mechanism | Scope | Status |
| --- | --- | --- | --- |
| Claude Code (claude-agent-acp 0.93.0) | `session/new` and `session/load` `_meta.claudeCode.options.settings.deniedMcpServers: [{serverName}]`. The Agent SDK merges `deniedMcpServers` from every settings source, its programmatic tier included, and doesn't start a denied server. | Per session, so per project | Verified |
| Codex (codex-acp 2.2.2) | `CODEX_CONFIG={"mcp_servers.<name>.enabled": false}` in the adapter's launch environment; the adapter merges it into every session's config. | All projects; applies when Codex restarts (Native restarts it once idle, or on "Apply to running sessions") | Verified, with the limit below |
| Cursor | None known. `cursor-agent acp` takes no session config for MCP. | — | Shown as "can't" per server |

## How it was verified

A probe outside the app (`/tmp/mcp-overrides/acp_probe.py` during development) started each adapter,
created one session in a scratch folder without prompting the model, and listed the MCP server
processes the agent started. The user's own config files were read but never written.

- Claude Code: without overrides `rea` started; with `deniedMcpServers: [{"serverName": "rea"}]` it
  didn't. In the app, a new session's `/context` dropped from 239.1k tokens (MCP tools 204.5k, 170
  `mcp__rea__*` tools) to 41.7k (MCP tools 7.1k, no rea tools).
- Codex: `CODEX_CONFIG` with `mcp_servers.rea.enabled = false` stops `rea` and leaves the other
  servers running, when the session brings no servers of its own.

## The Codex limit

codex-acp builds each session's config as `{...CODEX_CONFIG, "mcp_servers": <the session's own
servers>}`. A nested `mcp_servers` entry from `CODEX_CONFIG` is therefore replaced outright, and a
dotted `mcp_servers.<name>.enabled` key competes with the `mcp_servers` table inside Codex's
override map, whose order isn't fixed: in four runs with a session server present the server stayed
off three times. A `-c` override on `codex app-server` (tried through a wrapper) is replaced the
same way. Codex sessions in Native always bring the orchestration server, so the switch is best
effort there. The fix belongs in the adapter: add the session's servers as `mcp_servers.<name>`
entries instead of replacing the table. Codex defers MCP tool schemas behind its tool search, so a
server it still loads costs far less context than in Claude Code (about 23.4k input tokens for a
one-line prompt with or without `rea`).
