# Task scripts

Commands Native runs for you around a task's life: when it makes the task's worktree, when the task
starts, after each turn, before the worktree is removed, and once the task is deleted. Use them to
install dependencies, start and stop services, run a check after the agent works, or clean up
caches. They're set up in Settings ▸ Scripts (for every project), in each project's settings, or in
the repository itself, so a team shares them.

## Events

| Event | `NATIVE_EVENT` | Repository file | Runs | Time limit |
| --- | --- | --- | --- | --- |
| Setup | `setup` | `.native/setup.sh` | When Native makes a task's worktree, or brings one back when the task is unarchived, after copying its env files. The task waits for it (below). | 10 minutes |
| Task started | `task-started` | `.native/task-started.sh` | When a task starts, in its worktree or the project's folder | 1 minute |
| Turn finished | `turn-finished` | `.native/turn-finished.sh` | Each time the agent finishes a turn. A new turn's script stops the last one's if it's still running | 1 minute |
| Teardown | `teardown` | `.native/teardown.sh` | Before Native removes a task's worktree: archiving, deleting, deleting the project, cleaning up merged tasks | 1 minute |
| Task deleted | `task-deleted` | `.native/task-deleted.sh` | Once a task is deleted for good, after the undo window. Its worktree is gone by then, so it runs in the project's folder | 1 minute |

Setup and teardown go with worktrees, so a task that runs on a branch in the project's own folder
gets neither. Subagents don't trigger task-started or turn-finished; their task does. The time limits
are per event and can be changed in Settings ▸ Scripts (30 seconds to an hour); they cover all of an
event's scripts together.

The events are a fixed, typed set (`TaskScriptEvent` in `Packages/TaskScripts`). A new one needs a
case there, its row in this table, and a call from wherever it happens.

## Where scripts come from

For each event there can be a **global** script (Settings ▸ Scripts) and a **project** script. The
project's script is the repository's file when it has one, otherwise the one kept in Native's
settings for that project on this Mac. By default the global script runs first, then the project's;
a project can choose **Instead of the global script** per event, which with no script of its own
turns the global one off for that project. The first script that fails stops the rest.

| | Kept in | Shared | Labelled |
| --- | --- | --- | --- |
| Global | Native's settings on this Mac | no | Global |
| Project | Native's settings on this Mac, by the project's main checkout | no | This project |
| Repository | `.native/<event>.sh`, committed | with everyone who clones it | From the repo |

**Repository scripts** are read from the project's main checkout, never from a task's worktree, so a
pull request opened as a task can't supply its own. Whoever commits to a repository can change them,
so they don't run on a Mac until its user allows them for that project: the switch "Run scripts from
the repo" in the project's settings, or **Allow and Run** when a new worktree's setup asks. Until
then, setup waits for that choice (Run Without It goes on with the global script only), and other
events run without the repository's script and say so once in the log.

## How they run

- **Shell.** A script that starts with `#!` runs with the interpreter it names, so a committed file
  works whatever shell each person uses: start repository files with `#!/usr/bin/env bash` (or `sh`,
  `zsh`, `python3`…). Any other script runs with your login shell (`$SHELL -c`), non-interactively,
  so aliases and functions from `.zshrc` aren't there.
- **Environment.** The one your login shell gives (`PATH`, API keys), the same agents get, plus the
  variables below.
- **Folder.** The task's folder: its worktree, or the project's folder. Use `$NATIVE_WORKTREE_PATH`
  rather than the script's own location, which for a committed file is a temporary copy.
- **Background work.** A script is done when it exits. A server it starts in the background
  (`npm run dev &`) keeps running, with its output dropped; stop it in teardown.
- **Stopping.** Stop (in the banner, the log or Settings' test) and the time limit end the script
  and everything it started.
- **Where it runs.** Through `Packages/Exec`, on the machine the project is on.

### Variables

Every variable is set for every event, empty when Native doesn't know it.

| Variable | What it holds |
| --- | --- |
| `NATIVE_EVENT` | `setup`, `task-started`, `turn-finished`, `teardown` or `task-deleted` |
| `NATIVE_PROJECT_PATH` | The project's main checkout |
| `NATIVE_WORKTREE_PATH` | The task's folder, where the script runs |
| `NATIVE_BRANCH` | The task's branch |
| `NATIVE_BASE_BRANCH` | The branch the worktree was made from (setup) |
| `NATIVE_TASK_ID` | The agent's id for the task; empty during setup, which runs before the task exists |
| `NATIVE_TASK_TITLE` | The task's title; empty during setup |
| `NATIVE_AGENT` | The agent's id, such as `codex` or `claude-code` |

Setup scripts also get `NATIVE_WORKSPACE_PATH` and `NATIVE_ROOT_PATH`, the worktree and the main
checkout, the names they had before there were other events.

## What you see

- **Setup** shows above the task's conversation while it runs, with its output, Stop and Skip
  Setup. Messages you send meanwhile queue, and the agent gets them once setup succeeds or you skip
  it. A failure says which script failed and how (exit code, time limit), shows its last lines, and
  offers Retry, Skip Setup and Edit Script (Show Script for a repository's). A success can be
  dismissed, with its output a click away.
- **Other events** run quietly. The status bar's **Scripts** item, shown when the task has script
  activity, is the task's log: each run, its source, outcome, time and output, with Stop, Retry and
  Dismiss. A failure also shows above the conversation with Retry.
- **Teardown** never stops a worktree from being removed. When it fails, the archive's undo toast
  says so, and the Scripts log keeps it under "Archived and deleted tasks".

## Settings

- **Settings ▸ Scripts**: a row per event with Add or Edit, the projects that have scripts of their
  own, and the variables. The editor is monospace, with the time limit, the variables, and **Run
  Test**: in a scratch worktree of a project (made like a task's, with its env files, and removed
  afterwards) or for real in the current task's folder, with the output as it runs.
- **Each project's settings** (`ProjectScriptsSection`): "Run scripts from the repo", and per event
  what runs and where it comes from, with the project's own editor (After or Instead of the global
  script) or the repository's file, read-only.

All of it is stored as one JSON value, `taskScripts.configuration`, in Native's settings. Setup
scripts kept per project before (`git.setupScripts`) became those projects' own setup scripts the
first time this version ran; the old value stays, so an older Native still finds it.

## Organizations

Two policy keys (docs/enterprise.md):

| Key | Effect |
| --- | --- |
| `policy.taskScripts.userScripts` | `false`: scripts written in Native (global and per project) don't run, and their settings are locked |
| `policy.taskScripts.repositoryScripts` | `false`: `.native/*.sh` files are ignored, and "Run scripts from the repo" is locked off |

The V8 script runtime's `policy.scripts.enabled` is separate.

## Writing a good one

```sh
#!/usr/bin/env bash
# .native/setup.sh
set -euo pipefail
echo "Installing for $NATIVE_BRANCH"
bun install --frozen-lockfile
cp -n "$NATIVE_PROJECT_PATH/.env.local" . 2>/dev/null || true
```

```sh
#!/usr/bin/env bash
# .native/teardown.sh
set -uo pipefail
[ -f .dev-server.pid ] && kill "$(cat .dev-server.pid)" 2>/dev/null
docker compose down --remove-orphans 2>/dev/null || true
```

Print progress as you go: the banner shows each line as it arrives. Exit non-zero when something
the task needs didn't happen, so the task waits and you see why.
