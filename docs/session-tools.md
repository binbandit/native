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

## Adding a tool

A feature registers a `SessionToolContribution` with `SessionToolRegistry.shared`: its
`SessionToolSpec` (a stable id, the places it can live, the one it starts in), a title and a glyph,
its fact, whether its pane has something now, and its pane, or what its fact does if it has no pane.
The screen reads tools only from the registry, so features never reach into it, and the registry is
the session panel seam the lean-core plan (`docs/plans/lean-core.md`) builds modules on.

Where the user put each tool is a `SessionToolArrangement`, saved in user defaults
(`sessionTools.arrangement`) as only the places that differ from each tool's default.
