# Project actions

A project's quick scripts: named commands ("Test" runs `bun run test`, "Install" runs `bun
install`) that run with one click in the task's worktree. Native suggests them from what it finds in
the project, a team can commit them with the repo, and each user keeps their own.

## Where they are

| Surface | What it does |
| --- | --- |
| The header's **Run** split button (outlined, between Changes and Terminal) | Run the named action; while running, Stop, then End Now. The chevron opens the actions, Stop rows, repo actions, suggestions and Edit Actions… |
| The menu bar's **Run** menu | Run Last (⇧⌘R), Stop (⇧⌘.), every action of the visible task's project with the shortcut the user gave it, Edit Project Actions… |
| The command palette (⌘K) | "Run: Test", "Run: Install"… for the visible task's project, plus Run Last Action, Stop Action, Edit Project Actions… |
| The project's menu (sidebar "…" and context menu) | **Run ▸** the actions menu, including Run Last |
| Settings ▸ the project's page ▸ **Actions** | Add, edit, reorder and delete the user's actions; the repo's; every suggestion |

The header names the newest running action, or the project's last-run action, or the first of your
own actions, or the first from the repo. Its label stays the same while that action runs: a neutral
loader becomes Stop on hover, then End Now after interruption. With multiple runs, it names the
newest and shows the additional count. A successful run briefly shows a neutral checkmark (1.6s);
a failed run keeps a red five-dot mark, with exit code and duration in its tooltip. Hover shows Play
again. With no actions, Run is a single pull-down. A removed task folder disables only the run half;
the menu remains available. Every action is a command of its own, `projectActions.run.<name>`
("Run: Test"), named after the action, so a shortcut given to it in Settings ▸ Keyboard Shortcuts
runs Test in whichever project is in view (`docs/keyboard.md`, Project actions).

## Running

- **Where.** In the visible task's worktree (or a folder inside it, or inside the project's own
  checkout: the action's folder setting). From the project's menu with none of the project's tasks
  in view, it runs in the project's folder, in the background.
- **In the terminal** (the default): a tab of the task's terminal named after the action
  (`TerminalStore.run(_:for:)`) shows the command, its live output, and when it ends, how: "Test
  finished in 12s", "Test failed with exit code 1 after 3s", "Test was stopped after 4s", with Run
  Again. The tab's dot is green, red or gray; while it runs, the tab bar shows the elapsed time and
  Stop. Running it again reuses the tab (ending a run still going). It runs as a command typed in a
  new tab would: the terminal's shell (Settings ▸ Terminal ▸ Shell), as a login, interactive shell.
- **In the background**: no terminal; the command runs with the user's shell (`$SHELL -c`, in the
  login-shell environment, through `Packages/Exec`), and a toast says how it ended, with Show Output
  (the output, copyable) and, after a failure, Run in Terminal.
- **Stop** sends ⌃C, so the program can clean up; stopping again ends it. A background run's
  command is ended.
- **Run Last** (⇧⌘R) runs the header's named action in the visible task, including its first-action fallback.
- **Stop Action** (⇧⌘.) stops all running actions in the visible task; the run half stops only its named action.
- A terminal run that ends out of sight (another task in view, the panel hidden, another tab
  selected) says so in a toast with Show, which brings the task and the tab back.
- Every run gets `NATIVE_PROJECT_PATH` (the project's checkout), `NATIVE_WORKTREE_PATH` (the task's
  folder) and `NATIVE_ACTION` (its name), the same names the repo's event scripts get.

How a terminal run knows its exit status: on the Mac, libghostty starts commands through `login(1)`,
which hides the command's own status. So the command line (`ProjectActionLaunch.terminalCommand`)
frames the command in a small POSIX script that prints it, marks its start and end with OSC 133
(`133;C`, then `133;D;<status>`), and exits with its status. libghostty reports the end as a finished
command (`GHOSTTY_ACTION_COMMAND_FINISHED`) with the status and duration, which the tab's job takes.
A job whose shell ends before reporting (killed, or stopped) ends with the time since it started.

## Suggestions

Native reads the project's top level when its Run menu or settings appear (and when Native comes
back to the front), off the main thread (`ProjectDetector`, `Packages/ProjectActions`). Nothing it
suggests ever runs on its own: a suggestion is added, or added and run, or dismissed, by the user.

| Found | Suggests |
| --- | --- |
| package.json | Install, and every script except npm's install and publish hooks and `npm init`'s placeholder test, with the package manager the project uses: the `packageManager` field, else the lockfile (bun.lock(b), pnpm-lock.yaml, yarn.lock), else npm. `npm test`, `pnpm run dev`, `bun run test` (plain `bun test` is Bun's own runner) |
| justfile | Every public recipe that runs without arguments (not `_private` or `[private]`), as `just <recipe>`, with its doc comment |
| Makefile | Every named target (no files, patterns, special targets or variables), as `make <target>`, with its `## comment` |
| Cargo.toml | `cargo test`, `cargo build`, `cargo clippy`, and `cargo run` for a package with a binary |
| Package.swift | `swift build`, and `swift test` with a Tests folder |
| An Xcode project or workspace | `xcodebuild … -scheme <scheme> build` for up to three shared schemes, and `test` for schemes with tests |
| go.mod | `go test ./...`, `go build ./...`, and `go run .` when the root is a main package |
| pyproject.toml, requirements.txt, setup.py | Install with uv (`uv sync`), Poetry (`poetry install`) or pip, and pytest through the same tool when the project uses it |
| Gradle, Maven | Test and build (`./gradlew` or `./mvnw` when the project has the wrapper) |
| A Compose file | Compose Up and Compose Down |

**Order and dedupe** (`ProjectSuggestion.visible`): by what they do (install, test, dev, start, run,
build, lint, typecheck, format, the rest), then by where they came from (the project's own justfile
and Makefile first, since their recipes usually wrap the ecosystem's commands), then as the project
lists them. A command already added (spacing aside), dismissed, or found twice shows once or not at
all. Dismissing remembers the command, so it stays dismissed whichever file suggests it; Settings
can bring dismissed suggestions back. Added suggestions take a free name ("Test 2") when the project
already has one.

## Storage

- **The user's own**, per project, in preferences (`projectActions.actions`), keyed by the project's
  checkout path the way Git and the repo scripts key projects; dismissed suggestions and the last
  run alongside (`projectActions.dismissed`, `projectActions.lastRun`).
- **The repo's**, in `.native/actions.json` at the project's root, labelled "From the repo". Read
  only from the project's own checkout, never from a task's worktree, so a branch can't supply them.
  Edit the file to change them; "Copy to Mine" makes an editable copy, and "Copy as JSON" puts the
  user's own actions on the clipboard in this format, to commit.

```json
{
  "actions": [
    { "name": "Test", "command": "bun run test", "icon": "checkmark.seal" },
    { "name": "Web", "command": "bun run dev", "directory": "apps/web" },
    { "name": "Docs", "command": "make docs", "directory": "docs", "relativeTo": "project" },
    { "name": "Install", "command": "bun install", "runIn": "background" }
  ]
}
```

`name` and `command` are required; `icon` is an SF Symbol; `directory` is relative to the task's
worktree, or to the project's checkout with `"relativeTo": "project"`; `runIn` is `terminal` (the
default) or `background`. Unknown keys are ignored. An entry that can't be used is skipped, and
Settings lists why; a file that isn't JSON says so there, with Reload, and the user's own actions
keep working.

**Trust.** A repo action is a command from the repo, the same question as the repo's event scripts
(`.native/setup.sh` and the rest), so it shares their per-project switch ("Run scripts from the
repo") and the organization's `policy.taskScripts.repositoryScripts`. Until the project allows its
repo scripts, running a repo action first shows its command and asks: Run (this once), or Always
Allow for the project. With the policy off, repo actions are unavailable. If a repo action file exists, the header menu
shows a disabled lock row, "Off by your organization". Native policy currently has no organization-name
field. The user's own actions remain available.

## States

| Situation | What the user sees |
| --- | --- |
| No actions and nothing found | The Run menu says so with Add Action…, which opens the project's settings with the editor up; Settings lists what Native looks for |
| Files not read yet | "Looking for actions…" in the menu |
| An action's folder doesn't exist in the task | The tab says the action couldn't start, which folder is missing, Try Again and Close Tab; a background run's toast says the same with Edit Action… |
| The command fails | The tab's banner (or the toast) with the exit code and duration, Run Again (or Show Output and Run in Terminal) |
| The program ignores ⌃C | Stop becomes End Now |
| No task of the project in view | The project menu's Run says the action runs in the project's folder, in the background |
| A build without the terminal | Terminal actions run in the background, with the toast |
| The repo file is broken | A warning in Settings with the reason and Reload; the rest still loads |
| Deleting an action, dismissing a suggestion | Done at once, with Undo in the toast and on ⌘Z |

## Code

| Piece | Where |
| --- | --- |
| `ProjectAction`, `ProjectActionFile`, `ProjectSuggestion` (and `visible`), `ProjectDetector` and one detector per ecosystem, `ProjectActionLaunch` | `Packages/ProjectActions`, with tests against fixture repos in `Tests/ProjectActionsTests/Fixtures` |
| `TerminalJob` (a tab's command and how it ended) | `Packages/Terminal` |
| `TerminalPanelModel.run(_:)`, `stopJob(in:)`, `rerunJob(in:)`; the job banner, dot and controls | `native/Terminal` |
| `ProjectActionStore` (actions, scans, dismissals), `ProjectActionRunner` (runs, toasts, trust) | `native/ProjectActions/Model` |
| The header button, menus, toast, output sheet, repo-command question | `native/ProjectActions/Views` |
| The settings section and editor (`ProjectActionsSettingsSection(project:)`, embedded in the project's settings page) | `native/ProjectActions/Settings` |
| Commands and the menu bar's Run menu | `native/ProjectActions/Commands` |
| Launch wiring | `ProjectActionsWiring`, called from `NativeApp` and `CommandsWiring` |
