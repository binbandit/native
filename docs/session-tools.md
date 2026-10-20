# Session tools

The session screen is the conversation and the composer. Everything else on it (changes,
terminals, project actions, subagents, the branch's pull request, Open In) is a **tool**: a feature
the user turns on and places, which shows up only while it has something to show. With every tool
off, a task is the conversation and the composer, and nothing is missing.

It's behind the Session Tools gate (Settings ▸ Labs) while it's built; `SessionView` shows
`SessionToolsScreen` when it's on.

## Places

Each tool lives in one place, or is off (`SessionToolPlace`, `Packages/SessionTools`):

| Place | What the tool gets |
| --- | --- |
| Fact | A fact under the title, in place of a subtitle ("2 files +12 −3", "Dev :3000", "Cursor"). Its pane, if it has one, opens over the conversation from the fact. |
| Side | A tab beside the conversation, while it has something or is open. The pane docks beside the conversation when the window is wide enough to read both, and opens over it when it isn't. |
| Workbench | A tab under the composer, while it has something or is open. The workbench exists only while it has a tab. |
| Off | Nothing on the session screen. |

A tool that's on shows its fact wherever it lives, whenever it has one; the place says where its pane
opens. The rules are `SessionToolLayout`'s, tested in the package.

## The header

The window's title, and under it, in place of a subtitle, the task's branch and then each tool's
fact: `add-sentence · 2 files +2 · #128 · Cursor`. A fact is data, and it's the way in: clicking it
opens the tool in its place (or, for a tool without a pane, does what it does: Open In opens the
folder). The header has no buttons.

A side tool docks beside the conversation while the conversation keeps at least 520pt next to the
panel's 420pt (`SessionToolMetrics`): narrower, the conversation wrapped most lines of a reply.
Below that it drops over the conversation from the header, like a fact's tool, and Escape closes
it. The side panel opens without sliding, after `InspectorRoom` makes room, and closes without
animation, which keeps AppKit's split view out of a constraint loop.

## Native's tools

| Tool | Fact | Pane | Starts in | Key |
| --- | --- | --- | --- | --- |
| Changes | "2 files +12 −3" while there are uncommitted changes | The changes inspector; the files-changed card's Review opens it on the turn | Side | ⌥⌘1, ⇧⌘D |
| Subagents | "2 subagents" while there are any | Their conversations; a subagent's card opens its own | Side | ⌥⌘4, ⌥⌘I |
| Pull Request | "#128" once the branch has one | The pull request at a glance, or Create Pull Request | Fact | ⌥⌘5 |
| Open In | The default editor, with its icon | None: the fact opens the folder there | Fact | ⇧⌘O |

They're registered by `SessionToolsWiring`, one file each in `native/Wiring/SessionTools/`.

## Adding a tool

A feature registers a `SessionToolContribution` with `SessionToolRegistry.shared`: its
`SessionToolSpec` (a stable id, the places it can live, the one it starts in), a title and a glyph,
its fact, whether its pane has something now, and its pane, or what its fact does if it has no pane.
The screen reads tools only from the registry, so features never reach into it, and the registry is
the session panel seam the lean-core plan (`docs/plans/lean-core.md`) builds modules on.

Where the user put each tool is a `SessionToolArrangement`, saved in user defaults
(`sessionTools.arrangement`) as only the places that differ from each tool's default.
