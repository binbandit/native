# Warm worktrees

A task should start with the dependencies and build output its project already has. The controls
belong to the project, beside its existing scripts. Native uses the current Settings row, switch,
field, editor and task setup banner patterns, in light and dark. No new navigation or motion.

The default-off Warm Worktrees Labs switch keeps the existing behavior until design review passes.
With Labs enabled, Dependencies and caches has two rows: Folders to copy and Include local env files.
Folders starts empty (copying off), with common names suggested as placeholder text in a single-line
field. Enter comma-separated names or project-relative paths to enable copying; clear them to turn
it off. Local env files require consent. Setup stays in Scripts, using the existing editor, timeout
and Run Test. It runs once per worktree and holds messages; After creating a worktree runs in the
background without holding messages.
The existing repository-script trust and managed script policies still apply.

| State | Expected appearance and behavior |
| --- | --- |
| Default | Dependencies and caches heading, empty full-width field with suggestions, env off |
| Configured | A short comma-separated list in the same single-line field; neither row dims |
| Invalid path | Keep the user's input; explain that absolute, parent, .git and .env paths are skipped |
| Existing setup | One Setup row in Scripts, with Edit or Show for a repository script |
| Task ready | Existing setup notice says Copied followed by the folder names; output stays in its expandable task banner |
| Unsupported volume | Say that copies need both checkouts on the same APFS volume; setup still runs |
| Unsafe or existing paths | List skipped paths; never overwrite, traverse external links or use a full copy |
| Setup failure | Existing setup banner keeps Retry, Edit Script and Skip Setup; agent messages wait |

The result is the same task, ready to build, without reinstalling dependencies. The ideal common
path needs no decisions and no extra clicks. Per-project exceptions take one visit to settings;
the old workaround required manually finding and copying folders for every task.

Cache compatibility is the tool's responsibility. Absolute paths in compiler caches or virtual
environments may cause a rebuild. Links whose filesystem-resolved target is outside the task cause
that cache to be skipped; a setup command can recreate it. Workspace links need a safe existing target
in the completed task tree. Copies never refresh automatically in an existing task.
