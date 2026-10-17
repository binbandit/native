# Build a Native plugin

How to extend Native with a plugin: add a coding agent that speaks ACP, give every agent session
an extra MCP server, or add a multi-agent workflow, by writing a `plugin.json` into Native's
plugins folder, and how to check that Native loads it.

This file is the canonical description of Native's plugin format. Native serves it to agents as
the `build-a-native-plugin` skill (the `get_skill` tool of its `native` MCP server), so it's
written for an agent doing the work as much as for a person.

## What a plugin is

Everything Native runs with comes from plugins, its own agents included. There are two kinds:

- **Manifest plugins** are a `plugin.json` file and nothing else. They contribute data: agents,
  MCP servers and workflows. Anyone can write one, without rebuilding Native. This is what you
  write to extend Native for a user.
- **Built-in plugins** are Swift types compiled into Native (`native/Plugins/`). They can also
  run code: title sessions, react to session events, and give each session its own MCP server.
  See [Built-in plugins](#built-in-plugins) for that part of the API.

## Where plugins live

Each manifest plugin is a folder holding a `plugin.json`:

```
~/.native/plugins/
  my-plugin/
    plugin.json
```

Name the folder after the plugin's `id`. Native reads the folder at launch, and again when the user
clicks **Reload** in Settings ▸ Plugins. Folders are read in alphabetical order, after the
built-in plugins, so a plugin can't take over a built-in plugin's id. The user can turn any plugin
off in Settings ▸ Plugins. Changes apply to sessions started afterwards; agents start or stop right
away.

A plugin that fails to load is skipped and listed in Settings ▸ Plugins with the reason, such as
"Missing \"name\"." Other plugins still load.

## plugin.json

```json
{
  "id": "my-plugin",
  "name": "My Plugin",
  "version": "1.0.0",
  "description": "One sentence the user sees in Settings.",
  "agents": [],
  "mcpServers": [],
  "workflows": []
}
```

| Field | Required | Meaning |
| --- | --- | --- |
| `id` | yes | Unique across all plugins. Lowercase words joined with hyphens. Also the folder name. |
| `name` | yes | What the user sees. |
| `version` | no | Free-form, for the user. |
| `description` | no | One sentence: what the plugin adds. |
| `agents` | no | Coding agents, see [Agents](#agents). |
| `mcpServers` | no | MCP servers for every session, see [MCP servers](#mcp-servers). |
| `workflows` | no | Multi-agent workflows, see [Workflows](#workflows). |

Unknown fields are ignored. Nothing in `plugin.json` is secret: don't put API keys in it.

## Agents

An agent is a command that speaks the [Agent Client Protocol](https://agentclientprotocol.com) over
stdio. Native launches it once, through the user's login shell environment, and runs every session
of that agent through it.

```json
{
  "id": "gemini",
  "name": "Gemini",
  "symbol": "sparkles",
  "command": "gemini",
  "args": ["--experimental-acp"],
  "env": { "GEMINI_TELEMETRY": "off" },
  "resolveExecutables": {},
  "mcpConfig": null
}
```

| Field | Required | Meaning |
| --- | --- | --- |
| `id` | yes | Unique across every plugin's agents. Keep it stable: Native remembers sessions and their titles by it. |
| `name` | yes | What the user sees. |
| `symbol` | no | An SF Symbol name, shown where there's only room for an icon. |
| `command` | yes | The executable, looked up on the user's login shell `PATH`. |
| `args` | no | Arguments. |
| `env` | no | Extra environment variables. |
| `resolveExecutables` | no | Variables to set to the absolute path of a command on `PATH`, such as `{"CLAUDE_CODE_EXECUTABLE": "claude"}`, so an adapter runs the user's own CLI. |
| `mcpConfig` | no | Where the agent keeps its own MCP configuration (`"claude-code"`, `"codex"` or `"cursor"`), so Native can show the servers it already loads. |

Agents that don't speak ACP themselves need an adapter, usually run with `npx`. Pin its version so
upgrades are deliberate:

```json
{ "command": "npx", "args": ["--yes", "@agentclientprotocol/claude-agent-acp@0.93.0"] }
```

## MCP servers

Every MCP server a plugin lists is handed to every agent session when it starts or is reopened,
whichever agent it runs on. Give exactly one of `command` (a local server the agent launches over
stdio) or `url` (a server already running, over HTTP).

```json
{ "name": "docs", "command": "npx", "args": ["--yes", "@example/docs-mcp@2.1.0"], "env": { "DOCS_ROOT": "/Users/me/docs" } }
```

```json
{ "name": "tracker", "url": "http://127.0.0.1:7341/mcp", "headers": { "X-Team": "mobile" } }
```

| Field | Meaning |
| --- | --- |
| `name` | The server's name. Agents show its tools under it, such as `mcp__docs__search` in Claude Code. |
| `command`, `args`, `env` | A stdio server: the agent runs `command` with `args` and `env`. |
| `url`, `headers` | An HTTP server (MCP Streamable HTTP), with extra request headers. |

The agent starts stdio servers itself, so `command` must work for the agent: prefer `npx` or an
absolute path. Claude Code and Codex both accept HTTP servers. Pick a `name` other servers don't
use; `native` is Native's own.

## Workflows

A workflow is a reusable sequence of agent tasks the user starts from Native, such as "plan with
one agent, implement with another, review with the first". A broken workflow is listed with its
problems instead of failing the whole plugin.

```json
{
  "id": "explain-then-test",
  "name": "Explain, then test",
  "summary": "One agent explains the code, a different one writes tests from the explanation.",
  "symbol": "text.magnifyingglass",
  "input": { "label": "Which code?", "placeholder": "The retry logic in Uploader.swift", "required": true },
  "steps": [
    { "id": "explain", "title": "Explain", "prompt": "Explain {{input}} in {{project}}. Don't edit files." },
    {
      "id": "test", "title": "Write tests", "agent": { "differentFrom": "explain" },
      "approval": "Check the explanation before tests are written.",
      "prompt": "Write tests for {{input}} in {{cwd}}, based on this explanation:\n\n{{steps.explain.output}}"
    }
  ]
}
```

Workflow fields: `id` and `name` (required), `summary` (one sentence for the picker), `symbol` (an
SF Symbol), `input` (what the user is asked before it runs: `label`, `placeholder`, `required`)
and `steps`.

Step fields:

| Field | Meaning |
| --- | --- |
| `id` | Required. Other steps refer to the step by it. |
| `title` | What the user sees. Defaults to the id. |
| `kind` | `"agent"` (the default) runs `prompt` as an agent task, `"pullRequest"` opens a pull request from `pullRequest`, `"script"` runs `script` in Native's script runtime with the rendered `prompt` as its input. |
| `agent` | Which agent runs it: an agent id such as `"codex"`, `{"sameAs": "<step>"}`, or `{"differentFrom": "<step>"}`. Omitted means the run's default agent. Prefer the relative forms: they work with whatever agents the user has. |
| `continues` | A step id: run in that step's task, so the agent keeps its context. |
| `prompt` | The task, with `{{variables}}`. |
| `after` | Step ids that must finish first. Omitted means the step before; `[]` starts right away, in parallel. |
| `approval` | `true`, or a message saying what to check: the run waits for the user, who can edit the prompt. |
| `goal` | `true`, or `{"maxIterations": 8, "maxDuration": 1800, "maxCost": 5}`: keep working until the goal is met, within the budget. |
| `pullRequest` | `{"title": "{{title}}", "body": "...", "draft": false}`, for a `pullRequest` step. |
| `script` | The source a `script` step runs. |

Template variables: `{{input}}`, `{{title}}`, `{{cwd}}`, `{{project}}`,
`{{steps.<id>.output}}` (a finished step's result) and `{{steps.<id>.agent}}` (the agent it ran
on).

## Built-in plugins

Behavior, rather than data, needs a built-in plugin: a Swift type in `native/Plugins/` (or a
feature's folder) conforming to `NativePlugin`, listed in `BuiltInPlugins.all`.

```swift
protocol NativePlugin: Sendable {
    var manifest: PluginManifest { get }
    /// Names sessions after what they're about.
    var titler: (any SessionTitler)? { get }
    /// MCP servers for one session, in addition to the manifest's.
    func mcpServers(for session: SessionContext) -> [MCPServer]
    /// Session lifecycle hooks, delivered to every enabled plugin in order.
    func handle(_ event: SessionEvent) async
}
```

Every requirement but `manifest` has a default. `SessionContext` describes a session: Native's own
`clientID` (assigned before the agent creates the session, so per-session resources key by it),
the agent, the agent's `sessionID` once it exists, `cwd`, `title`, and `parentID` for subagents.
`SessionEvent` is one of `sessionStarted`, `promptSent`, `turnEnded`, `turnFailed`,
`permissionRequested` and `usageUpdated`. Native's notifications, sounds, session titles and
orchestration tools are built-in plugins written this way.

## Testing a plugin

1. Check the file is valid JSON: `python3 -m json.tool ~/.native/plugins/my-plugin/plugin.json`.
2. Check every `command` runs from a login shell, the way Native starts it:
   `zsh -lc 'command -v gemini'`. For a stdio MCP server, run its command by hand; it should wait
   for input rather than exit.
3. Have the user click **Reload** in Settings ▸ Plugins (or restart Native), then check the plugin
   is listed and enabled, with no load failure under it.
4. Try what it adds: an agent appears in the agent picker and starts (its status shows in the
   sidebar footer); an MCP server's tools show up in a new session; a workflow appears in the
   workflow picker.

If you're an agent writing a plugin for the user, tell them which file you wrote and that they need
to reload, and don't edit plugins you didn't write unless they ask.
