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
- **Task recency follows activity.** The host's startup snapshot and live summaries supply prompt
  dates even for completed tasks whose transcripts aren't open. Task lists use the latest known
  host, live-session or agent-listing date for both ages and order; opening history doesn't change it.
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
Foundation (UI-free, macOS + iOS, tested)    ACP · MCPServer · Git · GitHub · AIInstructions
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

## Experiments

New UIs, designs and behaviors ship as opt-in experiments first (see "Experiments behind flags" in
`docs/decisions.md`). It's one contract system with three tiers, all typed end to end:

- **Gate**: on or off, read at exactly one call site. The one place an experiment may be a plain
  `if`, because the declaration names that site.
- **Parameter**: a typed value (`Int`, `Double`, `String`, or a `ParameterChoice` enum) with a
  default and the values it allows. A saved value outside them reads as the default.
- **Variant**: alternative implementations for **extension points**. An `ExtensionPoint<Contract>`
  is a protocol plus the default implementation; a variant claims points with its own
  implementations while it's on. Two sources claiming one point is a conflict: the point falls back
  to its default and Labs says so. Contracts that aren't views are plain Swift, so engines resolve
  them from an `ExperimentSnapshot` off the main actor too.

The core (declarations, `ExtensionPoint`, resolution, `ExperimentStore`) is the UI-free
`Packages/Experiments`, tested with `swift test` and usable by the host and the companion. Every
experiment Native has is declared in `native/Experiments/NativeExperiments.swift` and listed in
`ExperimentCatalog.native`: id, title, one-line summary, stage (Labs or Beta), owner, review date,
what it touches and whether it needs a relaunch. Settings ▸ Labs shows all of it, with conflicts,
experiments past their review date, and Reset All (undoable). Values live in user defaults under
`experiment.<id>`; experiments that need a relaunch keep their launch value until the next launch.
Plugins add experiments too, through the same store and the same resolution rules. A code plugin
declares them in `NativePlugin.experiments` (gates, parameters, and variants claiming extension
points); a `plugin.json` declares gates that switch its own contributions and parameters that fill
`${experiment:<id>}` placeholders (`docs/plugins.md`, Experiments). `PluginRegistry` hands enabled
plugins' experiments to `ExperimentStore` (`PluginExperimentSet` checks them: ids namespaced by
plugin, `acme.fast-review`, and every problem reported per experiment), and applies manifest
effects to the manifests it gives everyone else, so turning a plugin off removes its experiments
and their claims at once. Each variant's claims resolve under its experiment as the
`ContributionSource`, so a conflict names the exact experiment, and its descriptor's `origin`
names the plugin; plugins that contribute implementations outside an experiment would add a second
source without changing how points resolve.

Adding a **gate**:

1. Declare `extension Gate { static let hideRetry = Gate(id: "hide-retry", title:, summary:, site:,
   stage:, owner:, reviewBy:) }` in `NativeExperiments.swift`.
2. List `Gate.hideRetry` in `ExperimentCatalog.native`.
3. At the one site: `@Experiment(.hideRetry) private var hidesRetry`, then `if !hidesRetry { … }`.
4. Run it, turn it on in Settings ▸ Labs, and check both states.
5. By the review date, delete the gate and its losing branch, or make it a setting.

Adding a **parameter**:

1. Define the value type, e.g. `enum TranscriptWidth: String, ParameterChoice`.
2. Declare it in a constrained extension: `extension Parameter where Value == TranscriptWidth {
   static var transcriptWidth: Self { Self(id:, …, default: .standard, domain: .allCases) } }`.
3. List `Parameter<TranscriptWidth>.transcriptWidth` in the catalog.
4. Read it: `@Experiment(.transcriptWidth) private var width: TranscriptWidth`.
5. By the review date, hard-code the winning value or promote it to a setting.

Adding a **variant**:

1. Find or add the extension point: a contract protocol (`TranscriptStyle: Sendable`) and
   `extension ExtensionPoint where Contract == any TranscriptStyle { static var transcriptStyle }`
   with today's behavior as the default. The point's owner exposes the seam.
2. Read it where the behavior happens: `@Resolved(.transcriptStyle) private var style: any
   TranscriptStyle` in a view, or `snapshot.implementation(of: .point)` in an engine.
3. Write the alternative as its own type in its own folder (`Styles/Bubbles/`), never as `if`
   branches in the default.
4. Declare `extension Variant { static let bubbles = Variant(id:, …, claims: [Claim(.transcriptStyle,
   BubbleTranscriptStyle())]) }` and list it in the catalog.
5. To promote it, make it the point's default and delete the variant; to drop it, delete its folder
   and declaration.

### Transcript styles

`TranscriptView` keeps scrolling and the loading and empty states; the rows come from the
`TranscriptStyle` in effect. `StandardTranscriptStyle` is the default; `BubbleTranscriptStyle` (the
Bubbles experiment, `native/Views/Transcript/Styles/Bubbles/`) shows the same rows as chat bubbles,
reusing the transcript's leaf views. Both get a `TranscriptStyleConfiguration`, which owns the shared
rules: which rows there are, which pending request answers the permission shortcuts, and how session
messages name other sessions.

## Persistence

| What | Where |
| --- | --- |
| Conversations | The agent's own store, via `session/list` and `session/load` |
| Titles, preferences, disabled plugins | `UserDefaults` (typed keys next to their owner) |
| Settings chosen per session (model, mode, effort), set back after `session/load` | `UserDefaults`, kept with the titles by `SessionTitles` |
| The mode each task is in (Build, Plan, Ask…) and the settings it changed | `UserDefaults` (`sessionModes`), by `TaskModes`; the user's own modes in `modes.custom`, a project's in `.native/modes/` |
| Where each task turn began, for the changes inspector's This Turn | `UserDefaults` (`git.turnBaselines`, the newest 200), by `GitTurnBaselines`; each points at a snapshot of the working tree kept as loose git objects only (no ref or index entry), which `git gc` prunes after a couple of weeks, when This Turn falls back to HEAD as it was when the turn began and says so |
| User plugins | `~/.native/plugins/<id>/plugin.json` |
| Scheduled resumes and similar durable app state | Application Support, owned by the feature |
| A project's settings (Settings ▸ Projects) | With each value's owner: the name on `Project`, the icon in `ProjectIconStore` (Application Support), git overrides in `GitSettings` by project path, the agent and model under `projectDefaults.<project id>`, scripts, AI instructions and actions with their features (each contributes a section), MCP and skill switches in their libraries |

## Related docs

- `docs/keyboard.md`: every shortcut.
- `docs/decisions.md`: decisions and why they were made.
- `docs/companion.md`: the iPhone companion layout, pairing and transport.
