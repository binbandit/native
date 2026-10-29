# Warm worktrees

A task should start with the dependencies and build output its project already has. The controls
belong to the project, beside its existing scripts. Native uses the current Settings row, switch,
field, editor and task setup banner patterns, in light and dark. No new navigation or motion.

The default-off Warm Worktrees Labs switch keeps the existing behavior until design review passes.
With Labs enabled, each project starts with common cache names selected and local env files off.
The user can disable copies, edit names or project-relative paths, and explicitly allow .env and
.env.local. The setup command opens the existing script editor, including its timeout and Run Test.
The existing repository-script trust and managed script policies still apply.

| State | Expected appearance and behavior |
| --- | --- |
| Default | Warm worktrees heading, a short APFS explanation, copies on, editable folders, env off, Add setup command |
| Copies off | Folder and env controls dimmed; setup command remains available |
| Invalid path | Keep the user's input; explain that absolute, parent, .git and .env paths are skipped |
| Existing setup | Edit or Show for a repository script, with the existing script editor |
| Task ready | Existing setup notice lists the cloned paths; output also stays in the task terminal |
| Unsupported volume | Say that copies need both checkouts on the same APFS volume; setup still runs |
| Unsafe or existing paths | List skipped paths; never overwrite, traverse external links or use a full copy |
| Setup failure | Existing setup banner keeps Retry, Edit Script and Skip Setup; agent messages wait |

The result is the same task, ready to build, without reinstalling dependencies. The ideal common
path needs no decisions and no extra clicks. Per-project exceptions take one visit to settings;
the old workaround required manually finding and copying folders for every task.

Cache compatibility is the tool's responsibility. Absolute paths in compiler caches or virtual
environments may cause a rebuild. Absolute or escaping links cause that cache to be skipped; a
setup command can recreate it. Copies never refresh automatically in an existing task.
