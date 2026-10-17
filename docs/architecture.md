# Architecture

## How Native works

```
 ┌───────────────────────────── Native.app ─────────────────────────────┐
 │  Views (SwiftUI, DesignSystem)                                       │
 │      │ user actions                                                  │
 │  AppModel ── agent runtimes ── PluginRegistry ── SessionTitles       │
 │      │            │                  │                                │
 │  SessionModel ×N  │      MCP server (orchestration tools)            │
 │      │ SessionState (ACP reducer)    ▲ tool calls                    │
 └──────┼────────────┼──────────────────┼───────────────────────────────┘
        │ ACP (JSON-RPC over stdio)     │ MCP (HTTP, per session)
   ┌────┴────┐  ┌────┴────┐  ┌──────────┴──┐
   │ Claude  │  │  Codex  │  │ any plugin  │   one subprocess per agent,
   │ adapter │  │ adapter │  │   agent     │   many sessions each
   └─────────┘  └─────────┘  └─────────────┘
```

- **Agents are plugins.** `PluginRegistry` collects agents (ACP launch commands), MCP servers,
  title providers and session hooks from built-in plugins and `~/.native/plugins/*/plugin.json`.
- **One process per agent, many sessions.** `AgentProcess` launches the agent with the user's
  login-shell environment. `ACPConnection` (an actor) speaks JSON-RPC and delivers events in wire
  order: when a request returns, every update sent before its response has been applied.
- **State is a reducer.** `SessionState` folds `session/update`s and the user's actions into a
  transcript (messages, tool calls, subagents, inter-session messages, plan, usage). It's pure and
  tested against captured traffic, and it's shared with the future companion app.
- **History lives with the agent.** Sessions are listed with `session/list` and reopened with
  `session/load`, which replays them. Native stores only its own additions (titles, order, goals).
- **Subagents** are child sessions: announced by agents (the ACP subagents RFD) or started by
  Native's orchestration tools on any agent. Both look and behave the same in the UI.

## Module layout

Today most code lives in the app target, organized by feature folder, with UI-free libraries in
`Packages/`. The target is compiler-enforced boundaries: each layer is a SwiftPM target, so a
feature can only use what other modules make `public`, and parallel work rarely touches the same
files.

```
Foundation (UI-free, macOS + iOS, tested)    ACP · MCPServer · Git · GitHub
        ▲
Core (state, plugins, engines)                NativeCore: AppModel, SessionModel, agent runtimes,
        ▲                                     plugin API + registry, titles, limits, goals and
        │                                     workflows engines, orchestration host
DesignSystem (tokens + components)            DesignSystem
        ▲
Features (UI)                                 TranscriptUI · ComposerUI · SidebarUI · SettingsUI ·
        ▲                                     SubagentsUI · GitUI · GitHubUI · UsageUI ·
        │                                     AutomationUI · HomeUI · StatusBarUI · Sounds
App (composition root)                        native/: NativeApp, RootView, scenes, menu commands,
                                              assets. Wires features together.
```

Rules:

- Dependencies point down only. **Features never import other features**: when one feature
  needs another (commit UI → "Create Pull Request"), it exposes a hook (a closure or protocol) and
  the app wires the two together.
- Foundation targets have no SwiftUI and no app knowledge. Core has no views.
- Each target has tests for its logic; views get previews with fixtures.
- Shared, app-wide behavior (shortcuts, plugins, design tokens) is defined once: `docs/keyboard.md`,
  `PluginRegistry`, `DesignSystem`.

### Migration

The move is mechanical and happens in small PRs once the current feature work lands:

1. Consolidate `Packages/*` into one `Packages/NativeKit` package with one target per library
   (single `Package.swift`, one `swift test`).
2. Move models, plugins and engines into `NativeCore`, making their API `public` and keeping
   internals internal.
3. Move `DesignSystem`, then each feature folder, into its own target.
4. Leave `native/` as the thin app: entry point, root view, commands, assets.

## Persistence

| What | Where |
| --- | --- |
| Conversations | The agent's own store, via `session/list` and `session/load` |
| Titles, preferences, disabled plugins | `UserDefaults` (typed keys next to their owner) |
| User plugins | `~/.native/plugins/<id>/plugin.json` |
| Scheduled resumes and similar durable app state | Application Support, owned by the feature |

## Related docs

- `docs/keyboard.md`: every shortcut.
- `docs/decisions.md`: decisions and why they were made.
- `docs/companion.md`: the planned iPhone companion and what it requires of the Mac app now.
