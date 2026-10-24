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
  Restart action. Diagnostic snapshots drain pending stderr without waiting for its callback or
  for a process holding the pipe open to exit. Only intentionally stopped or previously initialized
  agents return to idle; a failed launch must never be presented as ready to start a task. A task
  requested during an agent restart stays in Starting until the whole restart finishes. If it fails,
  Restart and Retry restarts the agent and continues the same task, keeping its draft and prepared workspace.
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
- **Transcript artifacts retain their bytes.** User attachments, agent images and tool results,
  including raw MCP content and embedded binary resources, open through the task's artifact viewer
  model. Images zoom and pan in place; other files use native previews. Host files use the existing
  file API, embedded bytes work offline, and opening a remote URL never downloads it. Temporary
  preview copies are private to the viewer and removed when it closes. Copy and Save As keep the
  original bytes; Finder is offered only for an existing file on this Mac.
  User-message attachments form one trailing-aligned group above the bubble. Mixed image and file
  tiles share a height; a lone image keeps its aspect ratio. File sizes come from attachment metadata
  carried through host echoes or embedded bytes, with an unavailable label when history has neither.
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
  iPhone's compact width is the companion layout. The separate companion target uses a
  `NavigationSplitView` to show Tasks beside the conversation at regular horizontal size classes,
  including the iPhone Duo inner display. Folding does not replace the navigation tree; selection,
  unsent messages and transcript anchors belong to window-owned task state (`docs/companion.md`).

MCP sign-in follows the same host boundary: `MCPLibrary.startSignIn` selects the task's command
runner, while its sheet opens the authorization link on the client. `Exec.CommandInput` carries
private terminal input locally or through `_native/exec/input` on the paired connection. The host
checks command ownership and the `runCommands` grant. OAuth and credential storage remain with the
agent CLI; see `docs/agents.md`, "MCP server sign-in".

### Resource percentages

The status bar, its tooltip, and the resource panel's process rows and totals show CPU as a
percentage of the sampling machine's total CPU capacity, from 0 to 100. `ProcessSampler` normalizes
CPU time by elapsed time and that machine's active logical processor count using `Exec.ProcessCPUUsage`.
Clients format the normalized value without dividing by their own processor count. Group and overall
totals are capped at 100 to account for skew between sequential process reads. For example, 395% of
one core is 49.375% of an eight-core machine, displayed as 49%.

Memory stays in bytes of physical footprint, as in Activity Monitor; its tooltip compares the total
footprint with physical RAM. It has no per-core scaling.

### GitHub account selection

Settings > General > Accounts lists and switches the GitHub accounts on this Mac. The Mac sidebar
footer shows only the selected avatar and name beside Settings; clicking it or choosing Go > GitHub
Account opens General at the Accounts group. A signed-out footer shows just Settings.
`GitHubAccountsModel` lists all
accounts from `gh auth status --json hosts`, loads names and cached avatars asynchronously, and
remembers one chosen login per host in Native's defaults. Without a choice it follows gh's active
account. `GitHubCLI` checks the selected login against gh's active account before requests. It never
retrieves tokens or reads gh's credential store. To use an inactive account, activate it with
`gh auth switch` in a terminal and check accounts in Native. Native does not change gh's active
account itself. It resolves Git URL rewrites and pins requests to the selected host. API and search
requests do not inherit the repository override from `GH_REPO`. The status check cannot lock gh's
configuration against a concurrent external account change.
Switching clears account-specific inbox, branch and review-page caches. An unavailable selected
account fails with sign-in guidance instead of silently using another account. Cross-host checkouts
need a default remote set in gh when their target is ambiguous; unresolved SSH aliases need a remote
URL with the GitHub hostname. Account controls are hidden on iPad
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

New Task's `NativeComposeTask` gate adds Quick Entry over the selected task. Its draft and
removable selection context live in `native/NewTask/QuickEntryModel`; writing and dismissing
the panel create no session or workspace. Start hands the message to the existing `StartingTask`
pipeline. A background start leaves selection alone, and its confirmation follows the starting
task to its finished session. During the first slice, Expand hands the same draft to today's
full New Task view. Compose's page and the shared well's pre-start presentation follow later.

### Home Next

`NativeHomeNext` (Settings > Labs > Next) defaults to off. `HomeDetail` switches to
`native/HomeNext/`: one centered reading column with a task title, the existing shared
`ToolCallView` approval, Up next, and a quiet working-status line. The composer owns the
annotated approval replacement; Home must embed that component when it lands, never copy it.
The sidebar owns the shared `TaskSignal`; Home uses it for the current ask and Up next rows.

`HomeAskOrder` in `Packages/TaskList` puts approvals before questions, plans, and failures,
oldest within each kind. The ask being read stays put when another arrives. Answering uses the
exact `SessionModel` and tool-call request displayed, including subagent requests. Home records
a receipt and advances when the model acknowledges an answer. Questions embed the composer's
`AgentQuestionSection`, with the same digit keys, multiple-question paging and free text. Plan
permissions embed `ComposerPlanSection` in its numbered review presentation (first five steps,
then Show more), using only the current turn's checklist. The exact permission proposal always
stays visible in the shared `ToolCallView`, with Approve Plan and Revise from its permission buttons.
Session-wide progress from earlier turns cannot replace the proposal being approved.

Failures use `ErrorState` in its reading layout: what happened, recorded recovery from the current
turn, error output, Retry and Open Task. `TurnFailureContext` in ACP includes live host recovery
notices and replayed recovery markers, keeping earlier turns' errors and recovery out of this
explanation. Retry asks the existing session to check completed work and
continue, preserving the draft; a disconnected in-process agent instead opens its task to reconnect.
Home retains the exact question or permission on screen, including subagent asks. An answer that
cannot reach the host stays on screen with its error and no success receipt. Finished today includes tasks
with a known successful turn completion today, five at a time; unknown history is not called done.
The sidebar still needs to fold its asks to their title on Home.

For isolated Debug checks, enable the gate with Settings > Labs > Next or
`defaults write dev.binbandit.native.dev.<name> experiment.NativeHomeNext -bool YES`, then launch
with `-nativeHomeNextFixture busy` for inert preview models. Other fixture values are `quiet`,
`first`, `empty`, `loading`, `recovery`, `narrow`, `question`, `questionText`, `questions`,
`plan`, `planText`, `planRetained`, `failure`, `failurePaused`, and `questionFailure` (a read-only sink
exercises answer delivery failure).
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

### All in view sidebar

The `NativeSidebarNext` gate (Settings ▸ Labs ▸ All in view) defaults to off. Slice 1 replaces
Quiet projects: project names keep the folder's spelling in Geist 600, and task rows show titles
at rest. `TaskSignal` owns the status language on the loader's 240-unit grid, with neutral working,
paused and limited states, amber requests, a red failure and an accent unread dot. Its optional
working view accepts animation variants without duplicating the other states or Reduce Motion.
Existing surfaces keep `StatusIndicator` until their gated redesign adopts `TaskSignal`.

Requests show a two-line sentence and a mono waiting clock, using the request's arrival timestamp
from ACP or the host event log. The grid breathes for its first 60 seconds and for four seconds
when the scene becomes active, then holds still. Reduce Motion is always still. The keycap marks
the oldest reachable ask across projects and child tasks, using the same request identity as ⌘Y.

Slice 2 adds `TaskPeek`: Space in the sidebar, the signal button, force click and the context menu
all open one 600pt popover without changing selection. A visible row supplies its anchor; hidden
rows and Settings use the window anchor. The model routes captured requests to their owning
session and checks identity again before answering. Questions, plans and commands with unknown
or irreversible effects open Peek from ⌘Y; a small ACP vocabulary permits routine approvals.
Peek reuses `AnnotatedApprovalView` and `AgentQuestionSection`, including command explanations,
instruction recovery and the hold for irreversible approvals. Recovered failures use their live signal;
unrecovered failures expose the real notice and the model's recovery action.

Selection, menus, ordering, pins, archive and keyboard navigation remain shared with today's
sidebar. All tasks stay visible in this slice; the rejected three-recent-task fold is removed.
Slice 3 keeps the platform's full sidebar hide. Back and forward remain beside search, followed by
one amber signal while a reachable task has an ask or an unresolved failure. Its count is per task,
including child asks under their parent, independent of sidebar filters and project folding.
The popover lists oldest asks first, then failures; a click or Space opens the same `TaskPeekView`
in place. Answering returns to the remaining list, and resolving the last task dismisses it.
The current task and draft stay untouched until Open Task. No second approval or status view is used.
Fold by day and optional row facts remain later slices. Enable before an isolated launch with
`defaults write dev.binbandit.native.dev.<name> experiment.NativeSidebarNext -bool YES`.

The sidebar's filter and sort controls also offer "Show agent icons", on by default. This only
hides agent artwork; working, attention and unread indicators stay visible. Archived tasks appear
under their project names in project order in both sidebar presentations.
All in view already omits agent artwork; the preference never hides its status signals, including
while renaming a task. The isolated Debug fixture `-nativeSidebarFixture trio` includes grouped
archives and a simulated Refresh failure followed by a successful Retry.

A project's Refresh action (its menu, File menu and command palette) re-reads all of its task
checkouts, including pinned and filtered-out tasks, once per checkout. Pull-request lookups bypass
the normal cache and wait for fresh results. Removed archived worktrees stay put away. A neutral
loader marks the project while work runs; failures retain the last known state and offer Retry
with recovery guidance. Remote git runs on the task's host; unavailable remote pull-request reads
are reported rather than running against a local folder with the same path.

### Plainly Settings

`NativeSettingsPlainly` (Settings ▸ Labs ▸ Plainly settings) defaults to off. `SettingsPageMap`
reads the gate and supplies the same ordered destinations to Settings and the command palette.
The screen passes the presentation through `settingsPlainly`; feature controls retain their
existing models and storage. The original page IDs remain deep links to sections in the new map.

The first slice groups the five personal pages without a heading, then Tasks (New Tasks, Agents,
While You're Away, Writing Style), Work (Git, Terminal, Search, Usage), Native (Features, Updates),
and Projects. Tools & Skills appears when either library is on; Labs remains available unless policy
forbids it. Usage stays in Settings by product decision. Modes are editable from New Tasks while
there is no separate Modes feature switch. Sounds joins Notifications, GitHub and Scripts join Git,
Sleep and paired devices join While You're Away, and enabled Celebrations join Appearance.

New Tasks owns the existing agent model and effort defaults, starting mode and workspace choice.
A project's agent, model and workspace controls move there with project scope; branch prefix stays
on its project page. Search follows the moved rows. `SettingsPlainlyCopy` supplies row text,
accessible control names and search titles together. The inheritance popovers, context accounting,
feature presets, agent detail pages and the shared overnight receipt belong to later slices.

### Fine print approvals

`NativeComposerNext` is an off-by-default Labs gate for the composer and its approval state. Enable it
with Settings > Labs > Fine print, or set `experiment.NativeComposerNext` as a boolean in the
isolated app's defaults. The rejected quiet-settings-line experiment has been removed.

`AnnotatedApprovalView` in `native/Approvals` is the shared approval for the composer and future
Peek and Home hosts. `SessionApprovalView` connects it to model actions. Only the oldest request
owns shortcuts; the primary transcript leaves its response controls to the composer while enabled.
The ordinary composer and approvals are unchanged with the gate off.

At rest the gated composer is one field and a model-name control. `ComposerSettingsControl`
opens model, effort, permission consequences and the agent's extra options in one popover;
its MCP page embeds `MCPSessionPanel`. Picks still go through `SessionModel.pick`, including
remembering successful choices and rejecting forbidden permission modes. `SettingsSourceLabel`
is shared with New Tasks: personal choices need no tag, agent defaults name the agent, and
managed permission rows name the configured organization. The existing policy
catalog governs permission modes and MCP servers; it does not supply model locks or an offline
web-search switch. Web search is editable only when the agent offers a config option for it.

`Packages/ApprovalAnalysis` matches literal commands against bundled, versioned JSON knowledge,
with additive plugin and managed-policy contributions. It never executes commands or inspects files
or the network. Unsupported syntax makes no claims. Conventional cache locations are lexical
labels, never proof that deletion is safe. `native/CommandKnowledge` provides client-local unknown
program counts and diagnostics, behind the same off-by-default Fine print gate. Policy can disable
counting; Settings can purge it; nothing exports it. See [command knowledge](command-knowledge.md)
for the schema, coverage, extension precedence, and storage contract. Host-side measurements remain
a later slice, subject to managed network policy.

Irreversible requests use the tested `ApprovalHold` state machine: 0.6 seconds, early release
cancels, 0.4 seconds of acknowledgement, five-second accessibility confirmation, and no Always
Allow. Platform key monitoring and haptics live in `native/Platform`. An alternative instruction is
queued through `SessionModel.instructInstead` before declining the original request. ACP never
receives an edited tool call, and the ordinary draft is kept.

### Task well

`NativeTaskWell` is an off-by-default Labs gate selecting the task-tools screen with a centered
activity capsule instead of the facts header and tool buttons. `TaskActivityNarration` in ACP projects
reported tool activity and counted plan steps; `TaskWellWiring` connects the existing tool models.
The open well reads worker identity, managed policy and cached tool summaries. Shells and Dev
runs share the existing terminal workbench; its add menu reuses project actions. Subagents use a
roster before opening their existing inspector. Requests lead to the existing composer or child
request surface, and turn outcomes reuse detected Changes. The shared `TaskSignal` supplies the status vocabulary and finite attention animation.
The behavior, tool order and remaining slices are described in `docs/session-tools.md`.

### Changing a task's agent (Labs)

`change-agent` is off by default. Change Agent prepares an unsent ACP conversation on another
installed plugin agent in the task's existing folder. The user chooses from the new agent's live
model choices and reviews an editable handoff before the first prompt. `TaskHandoff` in ACP
assembles bounded visible-message excerpts, the goal, latest plan, reported edits, branch and
working-tree paths and the latest explicit question locally. It never sends reasoning or calls another model.

The model rejects running turns, retries, queued messages, pending approvals and active goals.
Cancel closes the unsent replacement. A failed preparation or send keeps the original task.
After an accepted handoff, the existing conversation chain preserves the original transcript,
sidebar position and pin, title, branch, worktree and unsent draft. A quiet divider names the new
agent; Earlier Conversation opens the original transcript read-only. Links survive relaunch.

This first slice is limited to this Mac. Paired-host coordination, a single combined transcript,
and carrying goal automation and its budgets across agents remain follow-up work. Pause a goal
before switching; its objective goes in the handoff, but its controller stays in the earlier
conversation. Disable the gate to hide entry points; existing conversation links stay readable.

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

Before the first message, Change Workspace replaces the empty agent conversation in the chosen
folder, retaining its draft, attachments, title, order and settings. The model blocks sends while
the replacement is prepared. Once a message is submitted, including a queued message, the task
keeps its workspace. Existing branches reuse their checkout when present; otherwise Native makes
a worktree. Creation receipts in the repository's local config identify task worktrees that can
be cleaned up, including after a draft is reopened. Cleanup requires that their original branch,
commit and clean working tree remain unchanged. Ignored
files, running setup commands, other tasks and user-owned worktrees prevent automatic removal.
Open terminal tabs and project actions must finish or close before the task moves, so their work
stays reachable in the original task.
Paired-host replacements stay in the remote index, never the local catalog or local draft recovery.
Explicitly chosen worktrees outside the host's managed folder are associated with the project's
paired checkout, so reconnecting can list their tasks again.

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

### Coordinator tasks (Labs)

`coordinator-tasks` defaults off. The local host persists explicit assignments separately from
agent-created subagents, and `TaskOrchestrator` checks that scope on each tool call. Creation uses
the project folder and an advertised read-only setting, bypassing workspace preparation. See
`docs/coordinator-tasks.md` for scope, message attribution, lifecycle and deferred work.

### Credential ownership

Native reads only its own credential stores. Agent MCP configuration (server lists and URLs) remains
readable, but agent-owned sign-in stays unknown unless reported by the agent. An anonymous connection
check cannot establish that the agent is signed out. Native-owned MCP secrets continue to support
connection checks; agents retain responsibility for their own authentication.

### Point and say (Fine print, slice 3)

With `NativeComposerNext`, the transcript and Changes pane share a quote context supplied by
`SessionView`. Cmd-L captures only a selection inside a registered Native source view, or the
explicit line-number range in `DiffView`. The platform adapter never reads another application's
selection or the pasteboard. Diff quotes retain their old/new side and original line numbers;
transcript quotes use the selected text block's line numbers. Removing a quote supports Undo.

`PromptQuote` stores snapshots as readable leading quote blocks in the existing draft. The gated
composer renders those blocks with numbers in its 24pt padding and edits the message separately.
Send, queue editing, failure recovery and unsent draft persistence therefore carry one text value.
The switch-off composer exposes that same readable text, so changing the experiment cannot hide
or discard context. File tokens are a display projection of canonical `@path` references;
`FileReferenceProjection` maps edits and selections back to those paths. Displayed counts never
enter the prompt. The existing repository monitor supplies uncommitted counts, with the latest
reported turn edits as a fallback for committed files; unavailable or binary counts stay absent.
