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
  A host agent that exits during initialization stays failed, with its diagnostic output and a
  Restart action. Only intentionally stopped or previously initialized agents return to idle;
  a failed launch must never be presented as ready to start a task. A task requested during an
  agent restart stays in Starting until the whole restart finishes. If it fails, Restart and Retry
  restarts the agent and continues the same task, keeping its draft and prepared workspace.
  When every installed, enabled agent has failed, `AppModel.agentStartupFailure` supplies Home
  and New Task with the same named recovery state (`NativeSetup.AgentStartupFailure`). New Task
  opens the agent picker for Restart or Agents Settings instead of preparing a task that cannot start.
- **Stop ends attributable processes.** ACP's cancel acknowledgement alone cannot prove a shell stopped.
  The host records the agent's descendants before sending cancel, gives it a short grace period,
  then freezes and terminates the known tree. Process start times guard
  against reused pids, and remembered children remain owned if their parent exits. A shared agent
  is not terminated while another task is using it: the stopped task remains Stopping with a
  warning until the other tasks finish or are stopped. Its next message reloads the agent.
  Snapshots cannot account for a process that forks and exits between observations. Without an ACP
  command-lifetime guarantee, the result is a failed turn warning that background commands may
  remain, never a promise of Stopped. Closing a task retains its pending cleanup. Immediate host
  restart finishes cleanup without waiting for siblings and leaves their turns for recovery.
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

### GitHub account selection

The Mac sidebar footer shows the GitHub account used by Native. `GitHubAccountsModel` lists all
accounts from `gh auth status --json hosts`, loads names and cached avatars asynchronously, and
remembers one chosen login per host in Native's defaults. Without a choice it follows gh's active
account. `GitHubCLI` retrieves a chosen account's token with `gh auth token --hostname --user` and
passes it only in its child process environment. It resolves Git URL rewrites before selecting
credentials and pins the request host to that credential's host. API and search requests do not
inherit the repository override from `GH_REPO`. It never runs `gh auth switch` or saves tokens.
Switching clears account-specific inbox, branch and review-page caches. An unavailable selected
account fails with sign-in guidance instead of silently using another account. Cross-host checkouts
need a default remote set in gh when their target is ambiguous; unresolved SSH aliases need a remote
URL with the GitHub hostname. The footer control is hidden on iPad
until account selection is carried by the remote-host protocol.

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

`Packages/Undo` keeps undo toasts and the window's undo stack in agreement. `RootView` supplies the
main window's undo manager to `AppModel.undoHistory`; the Edit menu uses it even when Home has no
text responder. Archiving registers undo before workspace work starts, and the same action handles
the toast, Cmd-Z and Redo. Expired deletions withdraw their actions from the stack.

### Migration

The move is mechanical and happens in small PRs once the current feature work lands:

1. Consolidate `Packages/*` into one `Packages/NativeKit` package with one target per library
   (single `Package.swift`, one `swift test`).
2. Move models, plugins and engines into `NativeCore`, making their API `public` and keeping
   internals internal.
3. Move `DesignSystem`, then each feature folder, into its own target.
4. Leave `native/` as the thin app: entry point, root view, commands, assets.

## Experiments

### Home Next

`NativeHomeNext` (Settings > Labs > Next) defaults to off. `HomeDetail` switches to
`native/HomeNext/`: one centered reading column with a task title, the existing shared
`ToolCallView` approval, Up next, and a quiet working-status line. The composer owns the
annotated approval replacement; Home must embed that component when it lands, never copy it.
The sidebar owns the shared status signal; Home currently uses `StatusIndicator`.

`HomeAskOrder` in `Packages/TaskList` puts approvals before questions, plans, and failures,
oldest within each kind. The ask being read stays put when another arrives. Answering uses the
exact `SessionModel` and tool-call request displayed, including subagent requests. Home records
a receipt and advances when the model removes the permission. Questions, plans and failures
open their task until the next slice adds their inline answers. Finished today includes tasks
with a known successful turn completion today, five at a time; unknown history is not called done.
On Home, the sidebar's asks should fold to their title when the new sidebar lands.

For isolated Debug checks, enable the gate with Settings > Labs > Next or
`defaults write dev.binbandit.native.dev.<name> experiment.NativeHomeNext -bool YES`, then launch
with `-nativeHomeNextFixture busy` for inert preview models. Other fixture values are `quiet`,
`first`, `empty`, `loading`, `recovery`, and `narrow`.
The fixture is absent from Release and Nightly and never opens an agent or writes project data.

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
what it touches and whether it needs a relaunch. Settings ▸ Labs shows the user-facing details,
conflicts and Reset All (undoable); owner and review dates stay in the declarations for maintainers.
Values live in user defaults under `experiment.<id>`; experiments that need a relaunch keep their
launch value until the next launch.
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

### Quiet projects sidebar

The `NativeSidebarNext` gate (Settings ▸ Labs ▸ Quiet projects) defaults to off. Its single
read in `SidebarView` selects the quiet project presentation: monospace project headers and task
marks only for activity, attention and unread results. The existing section, menus, selection,
ordering, pins, archive and shortcuts are shared with today's sidebar.

Each project shows its live, unread, failed, paused and limited tasks plus its three most recent
resting tasks, in the user's order. An open or renamed task stays visible. “n more” unfolds the
rest; filters and bulk selection expose their full scope. `TaskListFold` in `Packages/TaskList`
chooses the resting tasks without depending on the UI. Enable it before an isolated launch with
`defaults write dev.binbandit.native.dev.<name> experiment.NativeSidebarNext -bool YES`.

### Quiet composer

`NativeComposerNext` is an off-by-default Labs gate at the composer's resting controls. Enable it
with Settings > Labs > Quiet composer, or set `experiment.NativeComposerNext` as a boolean in
the app's user defaults before launch.
The editor keeps its identity as the session starts and finishes work; only its footer changes.
At rest, plain words open the agent, model, effort, autonomy and task-mode pickers. The agent entry
opens New Task With, since an existing conversation belongs to its original agent. Other
agent settings, attachments, goals and context remain reachable. Running turns and approval
requests keep today's composer until their own slices land.

### Transcript styles

`TranscriptView` keeps scrolling and the loading and empty states; the rows come from the
`TranscriptStyle` in effect. `StandardTranscriptStyle` is the default; `BubbleTranscriptStyle` (the
Bubbles experiment, `native/Views/Transcript/Styles/Bubbles/`) shows the same rows as chat bubbles,
reusing the transcript's leaf views. Both get a `TranscriptStyleConfiguration`, which owns the shared
rules: which rows there are, which pending request answers the permission shortcuts, and how session
messages name other sessions.

`SessionModel` owns one `TranscriptDisclosures` (the UI-free ACP state) for its lifetime. Both styles
receive it through the transcript environment, so switching sessions, recreating a transcript or
opening a subagent does not discard disclosure choices. Tool rows, exploration groups and long runs
start closed; pending approvals override the visible state without changing the saved choice.
Scroll positions remain per window in `SessionTranscriptMemory`.

### Task worktree preparation

Git chooses an immutable task base with `Repository.taskWorktreeBase`, fetching the configured
remote unless `policy.git.worktreeFetch` disables it. Failure falls back to the local commit;
`GitStore` carries that explanation into the task's setup notice. Before-commands run through
`TaskScriptCenter` before the fetch and checkout. After-commands start after env files are copied
and never hold a task's turns. The same script runner retains policy, timeout and cancellation;
`TaskScriptsTerminalWiring` exposes its capped output through `TerminalLog` tabs alongside
Project Actions' interactive terminal jobs. See `docs/scripts.md`.

## Persistence

| What | Where |
| --- | --- |
| Conversations | The agent's own store, via `session/list` and `session/load` |
| Titles, preferences, disabled plugins | `UserDefaults` (typed keys next to their owner) |
| Settings chosen per session (model, mode, effort), set back after `session/load` | The host's session record and closed-session choices; `SessionTitles` keeps the local fallback in `UserDefaults`. On load, saved choices win, then explicit per-agent Settings defaults, then the agent's reported values |
| The mode each task is in (Build, Plan, Ask…) and the settings it changed | `UserDefaults` (`sessionModes`), by `TaskModes`; the user's own modes in `modes.custom`, a project's in `.native/modes/` |
| Where each task turn began, for the changes inspector's This Turn | `UserDefaults` (`git.turnBaselines`, the newest 200), by `GitTurnBaselines`; each points at a snapshot of the working tree kept as loose git objects only (no ref or index entry), which `git gc` prunes after a couple of weeks, when This Turn falls back to HEAD as it was when the turn began and says so |
| User plugins | `~/.native/plugins/<id>/plugin.json` |
| Scheduled resumes and similar durable app state | Application Support, owned by the feature |
| A project's settings (Settings ▸ Projects) | With each value's owner: the name on `Project`, the icon in `ProjectIconStore` (Application Support), git overrides in `GitSettings` by project path, the agent and model under `projectDefaults.<project id>`, scripts, AI instructions and actions with their features (each contributes a section), MCP and skill switches in their libraries |

The latest finished turn's files-changed card also compares its recorded baseline with the working
tree on the session's host. This includes committed edits and shell commands that report no edit
tool call. Reported files stay first, with Git's net counts when available; other changed files follow.
The comparison includes other work in the same folder since the turn began, just like This Turn in
the inspector. Review carries those detected files into the inspector so it can name them if their
changes are subsequently undone. Detection runs when the task opens or a turn ends, and retries if
the repository or baseline arrives later. Its snapshots use the same five-second deadline and
2,000-untracked-file limit as baseline recording. Without a recorded baseline or a live turn time,
the card keeps the agent's reported edits rather than attributing a whole branch to that turn.

## Related docs

- `docs/keyboard.md`: every shortcut.
- `docs/decisions.md`: decisions and why they were made.
- `docs/companion.md`: the iPhone companion layout, pairing and transport.
