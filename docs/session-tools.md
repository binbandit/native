# Task tools

The task screen is the conversation and the composer. Everything else on it (changes,
terminals, project actions, subagents, the branch's pull request, Open In) is a **tool**: a feature
the user turns on and places, which shows up only while it has something to show. With every tool
off, a task is the conversation and the composer, and nothing is missing.

It's behind the Task Tools gate (Settings ▸ Labs, off by default) while it's built; `SessionView` shows
`SessionToolsScreen` when it's on.

## The well

The separate `NativeTaskWell` gate (Settings > Labs > The well) also selects this screen, replacing
its facts header with the approved centered 340 by 30pt capsule. It defaults to off. The title gives
way first, then the agent name, then the middle of the activity's object. Progress keeps its space.

At rest it names the agent. During a turn it describes the latest unfinished tool with ACP's kind
and reported command or file. Counted progress is available for reported plan steps only; the count
and accessibility description identify those steps. Unstructured test output never supplies a
denominator. A request keeps its own wording, including destructive verbs, and clicking it focuses
the composer and reveals today's transcript approval, opening the child conversation when its
request needs attention, including a request owned by a nested child. Child questions reuse the
existing question dock in that inspector, with
answers and dismissal routed to the child; no unrestricted child composer is mounted. The well
cannot approve or reject anything. A stop says Stopping until
the host confirms it ended; a scheduled retry says Reconnecting.

The latest turn's detected or reported file changes supply the landed outcome. Its status settles
within a second; Review opens that same turn in Changes, and the outcome stays in the capsule
without Review while Changes is open (the turn's card says "Reviewing"). Closing Changes returns
the capsule to rest. A waiting ask's reason is its own words as a lowercase reason ("to write
notes.txt"), never a softer verb. The title takes the toolbar's room up to the well, which gives
way first: its agent name goes, then it narrows to its compact width, before the title truncates. The turn
card becomes a record that opens Changes, with Commit only in the pane. A one-second light runs at
turn start and landing, never throughout work, and is absent with Reduce Motion.

Cmd-I opens the tool list in key order: Changes, Terminal, Dev, Subagents, Pull request (Option-Cmd-1
through 5). The list reuses `SessionToolsScreenModel` for Changes and existing terminal, project
action and pull request actions for the other tools. Subagents and the pull request appear only
when present.

Only the rows scroll when the list grows beyond its height limit; the status header, worker and
checkout stay visible. Up and Down reveal the highlighted tool, including after scrolling by hand.

The worker block reports the agent's selected model, machine, last measured turn duration and
reported context use. The checkout moves to the footer. Managed worker settings carry a lock;
the footer names the administrator once, using the configured organization name or "your
organization". Native never infers a company name or invents a locked model.

Terminal opens a shell tab under the composer. Dev reveals the newest existing project-action
run without restarting it, or opens the existing action chooser before the first run. Shells and
terminal actions share the same resizable workbench, tabs, Stop, retry and hide controls.
Its add menu offers a new shell and the existing project actions, so another run is always one
step away. Background actions retain their existing output sheet. Closing the workbench keeps its jobs alive. A remote
task names its machine and explains why its terminal cannot open on this Mac; it never starts a
local shell in a remote path from the well. Subagents opens a roster, with the shared task signals,
so every worker is reachable. The pull request row reads the shared branch cache and includes its
number, state and check summary. No new tool runtime or network request is introduced.
The old Task Tools gate and standard task screen remain available.

The well uses the sidebar's shared `TaskSignal` at its well placement, with the actual request
arrival driving its finite attention breath. The composer owns the annotated approval and the
well only routes attention to it.
Narrow Changes is described below. Existing managed agent, host, shortcut and repository-action
policies are reflected here.

### The title

With the well, the toolbar's leading edge is the task's identity, where a Mac document window has
its title: the name, then the project and branch, and the machine when it isn't this Mac. The
project is the task's project by name, never its worktree folder. Clicking the title, or Task ▸
Rename Task… while the task is in view, opens the title popover: the name to edit, then Project,
Branch, Runs on and Agent with its model. Return keeps the name, Escape puts it back, and
clicking away keeps it, as renaming in the sidebar does; an empty name goes back to the automatic
title, and ⌘Z undoes it (`AppModel.rename`). Managed worker settings carry a lock on the Agent row
and the popover's footer names the administrator once, as the open well's does.

### Placement

Settings ▸ Task Tools, listed while the well is on, holds one row per tool in key order. Changes
opens beside the conversation (taking its place in a narrow window) or over it, or is off;
Terminal, Dev, Subagents and the pull request are each on or off. A tool that's off never reaches
the well: it has no row there and its key does nothing. The choices are the same saved
`SessionToolArrangement` as the original Task Tools gate's, under each tool's stable id
(`changes`, `terminal`, `dev`, `subagents`, `pullRequest`), and Restore Defaults clears them.

### When GitHub is out of reach

When the network policy keeps GitHub out of reach (an air-gapped or internal-only install, or the
`github.cli` service turned off; `docs/enterprise/network-admission.md`), a task on a branch keeps its Pull request
row, dimmed with "Not available here", says why, and offers the one thing to do instead: Export
Patch… (also Task ▸ Export Patch…). It saves the branch's commits since it left the default branch
as one `git format-patch` mailbox, binary files included, for `git am` on a connected machine
(`Repository.branchPatch`). The row then says what was saved, how many commits, and that
uncommitted changes aren't in it; a branch with no commits of its own yet is told to commit first,
and one with merge commits (which a mailbox can't carry) to rebase first, never given a partial patch.
A managed network setting puts a lock in the row's key slot and names the administrator in the
footer. Export Patch makes no network request.

## Places

Each tool lives in one place, or is off (`SessionToolPlace`, `Packages/SessionTools`):

| Place | What the tool gets |
| --- | --- |
| Fact | A fact under the title, in place of a subtitle ("2 files +12 −3", "Dev :3000", "Cursor"). Its pane, if it has one, opens over the conversation from the fact. |
| Side | A tab beside the conversation, while it has something or is open. The pane docks beside the conversation when the window is wide enough to read both, and opens over it when it isn't. |
| Workbench | A tab under the composer, while it has something or is open. The workbench exists only while it has a tab. |
| Off | Nothing on the task screen. |

A tool that's on shows its fact wherever it lives, whenever it has one; the place says where its pane
opens. The rules are `SessionToolLayout`'s, tested in the package.

## Adding a tool

A feature registers a `SessionToolContribution` with `SessionToolRegistry.shared`: its
`SessionToolSpec` (a stable id, the places it can live, the one it starts in), a title and a glyph,
its fact, whether its pane has something now, and its pane, or what its fact does if it has no pane.
The screen reads tools only from the registry, so features never reach into it, and the registry is
the task panel seam the lean-core plan (`docs/plans/lean-core.md`) builds modules on.

A plugin adds tools the same way, from `NativePlugin.sessionTools` (`docs/plugins.md`). While the
plugin is on, each is listed after Native's own in the well, in View ▸ Tools and on Settings ▸ Task
Tools, with a summary and "Added by" its plugin, and follows the same rules: off means no row and a
key that does nothing. Its command (`sessionTools.<id>`) has no default key, so the user assigns one
in Settings ▸ Keyboard Shortcuts. Its row says what its fact says; choosing it opens its pane in its
place, as Changes does, or does what its fact does. A plugin's tool id starts with the plugin's id
(`acme.tickets`), so it can't take a built-in tool's place or saved arrangement, and it lives beside
the conversation or over it: the workbench holds only Native's terminals and runs
(`SessionToolSpec.isAllowed(fromPlugin:)`, tested in the package).

The screen model retains each presented contribution's close hook with its original session context.
Closing, replacing or revoking a pane runs that hook once, even after its plugin leaves the registry.
Pending opens cancelled before presentation have no close hook to run. Task continuations rebind
the model for newly opened panes; already-presented hooks keep their original session until closure.
`scripts/tests/session-tool-cleanup.sh <instance>` checks both side and over-conversation tools through
the app model harness.

Where the user put each tool is a `SessionToolArrangement`, saved in user defaults
(`sessionTools.arrangement`) as only the places that differ from each tool's default.

## Facts header and Changes

The gated screen shows the task title, then its branch (or folder) and the live Changes fact:
`feature-branch · 2 files +12 −3`. A clean repository has no Changes fact. Clicking the fact,
View ▸ Tools ▸ Show Changes (⌥⌘1), or the existing ⇧⌘D opens Changes. The transcript's Review
and file rows open the same panel on the latest turn; Commit retains the existing commit flow.
The panel retains the inspector's loading, failure, non-repository and clean states.

Changes docks when the task's available width can hold a 520pt conversation and a 420pt
panel. The docked panel stays at 420pt, including after state restoration, so dragging or restoring
a wider inspector cannot consume the conversation's reserve. Below 940pt it opens over the
conversation. Resizing preserves the selected tool, review scope, selected file and loaded range
diff. Escape closes the overlay ahead of composer actions, or the docked panel while focus is in
it. Opening and closing the inspector disables animation to avoid the prototype's split-view constraint loop. The threshold
still needs a visual check on the main Mac in both appearances.

The original Task Tools gate registers only Changes, with Side, Fact and Off placements.
The well adds the shared workbench and tool adapters described above, Settings ▸ Task Tools
to place them, and plugins' tools. The default-on transition remains a later slice.
The standard screen is unchanged while both Labs switches are off.

## Narrow Changes

With `NativeTaskWell`, a Changes pane that cannot fit beside the conversation takes its place.
The composer remains underneath, and Escape or Close Changes returns to the same conversation.
The 44pt header holds one file pop-up, its position and line totals, and the existing Commit action.
The pop-up includes This Turn, Uncommitted and Branch; partly staged files remain separate entries
under their staging areas. It also stages or unstages the shown uncommitted file, and a conflicted
file shows Stage beside the pop-up, so a resolved conflict can be marked without the list. Escape
closes it wherever focus is. Loading, missing-repository, clean, comparison fallback, binary, large
and failed-diff states reuse the existing Changes views. Other tools and the original Task Tools
switch keep their existing overlay behavior.

File markers use neutral tertiary letters in both well layouts: amber means "yours", and the
letter is enough. The diff is the shared `DiffView`, so selecting its lines quotes them into the
composer through the composer's own point-and-say (`NativeComposerNext`); Changes adds no
selection model of its own.
