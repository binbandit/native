# Task tools

The task screen is the conversation and the composer. Everything else on it (changes,
terminals, project actions, subagents, the branch's pull request, Open In) is a **tool**: a feature
the user turns on and places, which shows up only while it has something to show. With every tool
off, a task is the conversation and the composer, and nothing is missing.

It's behind the Task Tools gate (Settings ▸ Labs, off by default) while it's built; `SessionView` shows
`SessionToolsScreen` when it's on.

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

This step registers only Changes, with Side, Fact and Off placements. The existing subagent
card inspector remains available. The other tool facts and panes, workbench, Settings editor,
and default-on transition belong to later PRs. The standard screen is unchanged while Labs is off.
