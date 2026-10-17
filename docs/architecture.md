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

## Clients and hosts

Native is split into a **host**, which runs agents, commands and file access, and **clients**, which
show and drive it. The Mac app runs a local host (the durable background host, `docs/durability.md`)
and is also its first client. An iPad, an iPhone, or a Mac connected to a Mac mini or a Linux server
is a client of a remote host. Every client speaks the same host protocol: a Unix socket locally, an
end-to-end authenticated connection (paired by QR code) remotely.

What follows from that:

- **Only hosts touch the machine.** Spawning agents, running git or gh, reading project files,
  keeping the Mac awake and sampling processes happen on a host. Code that shells out takes a
  `CommandRunner` (`Packages/Exec`); a client gets one that forwards to its host.
- **Clients are platform-neutral.** Models, views and the design system compile for macOS and
  iPadOS. Platform-specific code (AppKit, NSWorkspace, window chrome, menu bar extras) lives behind
  small adapters in `native/Platform/`, with an iPadOS counterpart or a documented absence.
- **Every input is first class.** Pointer, touch and hardware keyboard all reach every action:
  hover-only affordances get a touch equivalent (a visible button, context menu or swipe action),
  touch targets are at least 44pt, and the shortcuts in `docs/keyboard.md` work on iPad keyboards.
- **Layouts adapt to width, not to platform.** A Mac window, an iPad in Stage Manager and an iPhone
  are points on one range: the sidebar and inspector become overlays at narrow widths, and the
  iPhone's compact width is the companion layout.

### Getting there

1. Rules now: no AppKit in models or shared views, no process spawning outside `Packages/Exec` and
   the host, and `Packages/*` build for iOS.
2. The host protocol carries everything the UI needs (sessions, approvals, git, gh, files, usage,
   limits), and its client library builds for iOS (durable host work).
3. `AppModel` talks to a host client instead of spawning agents itself; the Mac connects to its
   local host.
4. The app target adds the iPadOS destination, fills in the `native/Platform/` adapters, and gets an
   iPad layout pass on device.

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
- `docs/companion.md`: the iPhone companion layout, pairing and transport.
