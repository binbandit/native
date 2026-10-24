# Playtesting

How to run Native, drive it like a person would, and report what's broken, written for an agent that
has never seen it. Playtesting here is simulation testing: you get a private copy of the app, a
realistic workspace and a driver that can't touch anything else on the Mac, and you use Native the way
Brayden does every day. What matters most is whatever would stop him using Native to build Native:
losing work, a turn that hangs, a task he can't find, a review he can't do, a state that leaves him
guessing.

You report issues; you don't fix product code. If the guide or the driver gets in your way, say where.

## The rules

These come from [AGENTS.md](../AGENTS.md) and apply to everyone on this Mac. A playtest shares the Mac
with its owner: Brayden is often at it while you play, and a dozen agents build and run Native on it.

- **Leave the Mac usable.** `run-isolated.sh` queues app builds (three at a time, at a low priority);
  run any other `xcodebuild` through `scripts/dev/build-slot.sh`. Quit your instance whenever you
  aren't using it, even between scenarios.
- **Automate only your instance's process.** `scripts/dev/drive.sh` does this for you: it finds your
  instance by name and acts on that one pid, through Accessibility (`AXPress`, setting `AXValue`) and
  `CGEvent.postToPid`. Never send System Events `keystroke`/`key code`, never bring a window to the
  front, and never use coordinate clicks like `click at`: all of those land on whatever app has
  focus, often someone else's. The driver never raises or focuses a window (no `AXRaise`, no writes
  to a window's `AXMain` or `AXFocused`, nothing made frontmost), and every launch goes through
  `run-isolated.sh`, which opens the instance behind whatever is in front (`open -g`). Never launch
  Native any other way, and never a Release build.
- **Never open other apps or windows** (Finder, editors, terminals, browsers). Anything in Native that
  would open one (Open In, Sign in, a link, a file picker) is out of bounds; note that it exists and
  move on.
- **Never touch Brayden's Native**: the app in `~/Applications/Native.app`, its defaults
  (`dev.binbandit.native`), its data in `~/Library/Application Support/Native` and its host. Never
  kill a process you didn't start.
- **Never change the Mac**: no Wi-Fi or network changes, no signing agents out, no System Settings.
  [Failures on cue](#failures-on-cue) simulates each of those inside your instance.
- **Never act on real GitHub.** Pull Requests reads Brayden's own account through `gh`: look, but
  never comment, review, approve, merge or close there, and never push anywhere but the seeded clone's
  local origin.
- **Real sessions use Claude Code on Haiku at Low effort**, the cheapest; your instance defaults to
  it. Keep prompts tiny. Use another agent only when the behavior under test belongs to it.
- **Nothing counts while the screen is locked.** Windows aren't laid out then, screenshots fail and
  the accessibility tree is incomplete. `drive.sh <name> screen` says `locked` or `unlocked`; the
  driver warns on every command and refuses screenshots while locked. Never try to unlock or wake it.
- **Quit your instance as soon as a check is done**, and when you finish, remove it (about 6 GB) and
  your scratch folders. Memory and disk are shared.
- **No secrets in reports**: no tokens, keys, auth files or personal data in text or screenshots.
- **If you do change code** (playtesters normally don't), follow AGENTS.md "Saving work (Kite)": save
  with a bare `kt` from the repo root; never `git add`, `commit`, `reset`, `checkout`, `restore`,
  `stash`, `switch` or `rebase` in the shared tree; never `kt land`, `undo`, `go`, `publish`, `pr` or
  `ship`; never delete `.git/index.lock`.

## Run it

```sh
scripts/dev/run-isolated.sh playtest --build    # build only, into /tmp/native-dd/playtest (a few minutes the first time)
scripts/dev/drive.sh playtest seed              # projects to play with (below); run it while the instance is quit
scripts/dev/run-isolated.sh playtest            # build if needed, launch, print its pid and window id
```

`playtest` is the instance's name; pick your own if several of you play at once. Isolation means the
instance shares nothing with Brayden's Native or anyone else's instance:

| | Where |
| --- | --- |
| Build | `/tmp/native-dd/<name>`, bundle id `dev.binbandit.native.dev.<name>` |
| Settings | that bundle id's own defaults domain |
| Data (task list, search index, project icons) | `~/Library/Application Support/dev.binbandit.native.dev.<name>` |
| Background host and its sessions | its own launchd job, socket and database under `~/Library/Application Support/Native/Channels/<channel>` (the launch prints the channel) |
| Task worktrees | `~/.native/worktrees-dev/<name>` |

Instances start muted, with new tasks on Claude Code with Haiku at Low effort. Launching again (`run-isolated.sh playtest
--no-build` skips the build) replaces the app but leaves its host running, exactly like a person
quitting and reopening Native, which is how durability is tested.

```sh
scripts/dev/run-isolated.sh playtest --quit     # quit the app and stop its host and agents
scripts/dev/run-isolated.sh playtest --reset    # also forget its settings, data, host and worktrees
scripts/dev/run-isolated.sh playtest --remove   # reset, then delete the build; run this when you're done
```

The tree is shared and saved continuously, so the build can fail in files you didn't touch: someone
is mid-change. Don't fix their code. Wait a few minutes and build again, or play the last build you
have (`--no-build`) and say which commit it is (`git log -1 --format=%h` when you built).

## Set the stage

`drive.sh <name> seed` (with the instance quit) sets up a realistic workspace under
`/private/tmp/native-playtest/<name>`:

- **`native`**, a scratch clone of this repo (`git clone --local`). Its `origin` is a bare repo next
  to it, so commits, pushes and branch work stay on this Mac. This is the project for the daily loop:
  Native working on Native. Agents working in it follow its AGENTS.md, so they save with `kt` (in the
  clone, which is fine) and may try to build or launch Native: keep prompts small and end them with
  "Don't build or run the app."
- **`sample`**, a tiny Python repo with one failing test (`python3 -m unittest`), for quick, cheap
  turns.
- **Fake Agent**, a scripted agent from the host's tests, installed as a plugin for this instance
  only. It never calls a model, so it's free, and it fails on cue ([below](#failures-on-cue)).
- Both folders as the instance's projects, with Claude Code as the default agent.

Seeding again keeps the folders and rewrites the project list; `seed <folder>…` adds more projects,
and `seed --remove` deletes the folder. To see Native as a new user does, skip seeding:
`run-isolated.sh playtest --reset`, then launch.

Launch arguments go after `--`: `scripts/dev/run-isolated.sh playtest --no-build -- -appearance.mode dark`.

| Argument | What it does |
| --- | --- |
| `-appearance.mode light` / `dark` / `system` | Appearance, for checking both |
| `-nativeWindowFrame "x y w h"` | Places the window (points, from the bottom left of the main display), so screenshots are the same size every time |
| `-nativeDate 2026-12-25` | Pretends it's that day (celebrations, relative times) |
| `-defaultAgent <agent id>` | The agent new tasks start with; already `claude-code` |
| `-agentDefaults.claude-code.model <id>` | Claude Code's model; already `haiku` |
| `-agentDefaults.claude-code.effort <id>` | Claude Code's effort; already `low` |
| `-nativeOpenSession <agent>/<session id>` | Opens that session at launch (`docs/performance.md`) |
| `-pluginsDirectory <folder>` | Loads plugins from there; `seed` already points it at its plugins |
| `-experiment.<id> YES` | Turns a Labs switch on for this launch only (`NO` turns it off), e.g. `-experiment.NativeSidebarNext YES`; the id is the experiment's `id` in `native/Experiments/NativeExperiments.swift` |
| `-nativeHostRefused YES` | Acts as if background running were refused, to see the fallback (`docs/durability.md`) |
| `-quickEntryFixture selection` | With `NativeComposeTask` on, Cmd-N renders a Quick Entry preview state. Also accepts `empty`, `firstLaunch`, `failure`, `offline`, `narrow`, `devices`, `agents`, `projects`. Debug only; the device fixtures never connect to a paired host. Omit this argument for behavior checks. |
| `-composeTaskFixture ready` | With `NativeComposeTask` on, Shift-Command-N renders the Compose page with inert fixture content. Also accepts `empty`, `firstLaunch`, `failure`, `offline`, `held`, `narrow`, `agents`, `devices`, `twoAgents`, `folding`, `message`, `settled`. Omit for behavior checks. |
| `-taskWellPluginFixture YES` | Registers the inert Review Kit plugin for well/Task Tools checks: a long working side tool, a default-Off Runbook and failed over-conversation Notes. Debug only; disable Review Kit in Settings > Extensions. |
| `-taskWellManyTools YES` | With the Review Kit fixture, adds 25 enabled plugin tools to check overflow, scrolling and keyboard reveal. Debug only. |
| `-framePacing YES` | Logs dropped frames once a second (`drive.sh <name> logs --stream`) |

For a long transcript without spending anything, install the long-session fake agent
(`python3 scripts/perf/long-session-agent.py --install /private/tmp/native-playtest/<name>/plugins`):
it lists sessions of 20, 100 and 500 turns to reopen. `scripts/perf/fixture.sh` fills a sidebar with
30 tasks across four projects (it rewrites the project list, so seed again afterwards).

For the plugin fixture, write the well gate as a boolean before launch:
`defaults write dev.binbandit.native.dev.<name> experiment.NativeTaskWell -bool YES`.
To revoke a plugin while its pane stays onscreen, mark `policy.plugins.allowed` in
`policy.debug.managedKeys` before launch, initially allowing `review-kit` and the scripted agent's
plugin id (`playtest-fake-agent` for `seed`). Remove `review-kit` from that allowed list while a side
or over-conversation pane is open. Review Kit follows that policy live, as an installed plugin does.
Check that its pane and well rows disappear, its commands leave Keyboard Shortcuts, and reallowing
it leaves the old pane closed. This avoids Settings navigation closing the pane before revocation.
For overflow checks, also launch with `-taskWellManyTools YES` at a short window height. In light
and dark, open the well, scroll from Changes to Check 25 and back with the pointer or touch, then
use Up from no highlight to reveal Check 25 and Down/Up to traverse the full list. Keep the status,
worker and checkout visible. After scrolling away from a highlighted endpoint, press its arrow
again to confirm it is revealed even though the selection did not change. Return or Space must
open the highlighted tool; Escape must close the well.
In a background instance, edit an unsent draft after changing defaults to trigger a preferences
notification, wait for the removal, then clear the draft without sending it.

### Silent instances

Dev builds, previews and test harnesses are silent by default. `run-isolated.sh` passes
`-sounds.enabled NO -native.mute YES` at every launch; seeding and launch profiling also mute audio.
The shared `NativeAudioPolicy` blocks player creation, including Settings sound previews, even if
Sounds is enabled. System notifications carry no sound. Celebrations currently have no audio path.

Keep test instances muted on the shared Mac. On a dedicated audio test machine only, pass both
`-native.mute NO -sounds.enabled YES` and enable the Sounds plugin to test playback. These are
per-instance overrides; never change system volume or play audio to verify silence.

## Drive it

`scripts/dev/drive.sh <name> <command>` (or `just drive <name> <command>`). It compiles itself on
first use (a few seconds) and needs the instance running. `drive.sh <name> help` lists everything.

| Command | What it does |
| --- | --- |
| `tree [--depth N] [--frames] [--raw]` | The window's accessibility tree: role, label, `= value`, `#identifier`, `[disabled]`, `[focused]`, `[selected]` |
| `find <text> [--role R]` | Every match, numbered, with the nearest named element around it |
| `text [<text>]` | The text a person would read, under a match or in the whole window: the transcript, an error, a sheet |
| `press <text> [--nth N] [--role R]` | Presses a button, row, toggle or menu item (`AXPress`, or selects a row) |
| `press <menu button> [--item <text>]` | A button that opens a menu (`AXMenuButton`, `AXPopUpButton`): lists its items, or picks one, and never leaves the menu open |
| `set <text> <value>` | Writes a text field or the composer, as if typed in one go; `-` reads stdin |
| `type <text>` | Types into whatever has focus, a key at a time (for `/` and `@` lists); `\n` is Shift-Return |
| `key <combo>…` | `cmd+n`, `return`, `escape`, `shift+cmd+a`, `opt+cmd+up`, `ctrl+tab` |
| `key <combo> --hold <seconds>` | Holds each key combination before releasing it (0 to 3 seconds), for deliberate confirmation controls |
| `drop <composer\|transcript> <file>… [--phase hover\|drop\|exit]` | Delivers a fixture drag to the isolated Debug window's registered AppKit destination. Launch with `-debugAttachmentDropChecks YES`. Uses a private pasteboard, including a file's text representation to catch path insertion. `--text <text>` checks an ordinary text drop instead |
| `paste-files <file>…` | Delivers copied fixture files through the composer's paste handler using a private pasteboard |
| `menu <Menu> [<Item>…]` | Lists a menu with its shortcuts and disabled items, or presses an item |
| `action <text> <name> [--item <text>]` | Performs an accessibility action; `AXShowMenu` lists a context menu's items, or picks one |
| `scroll <text> <up\|down\|top\|bottom\|reveal>` | Pages the scroll area at or around a match, or scrolls the match into view |
| `wait <text> [--gone] [--timeout S]` | Waits (30 s by default) for something to appear or disappear |
| `focused` | The element with keyboard focus |
| `shot <file.png>` | Screenshots the window (no shadow, no sound); refused while the screen is locked |
| `windows` | The instance's windows, sizes, and whether another app's window covers them |
| `frame [x y w h]` | Reads or sets the window's frame (top left, points) |
| `logs [--last 10m \| --stream]`, `crashes` | This instance's log lines, and its crash reports |
| `processes` | The instance's app and host with every process under them (agents, their tools): the only ones you may kill |
| `seed`, `screen`, `pid` | The workspace, whether the screen is locked, the instance's pid |

Fine print has Debug-only state overrides for an existing fixture approval. Relaunch the isolated
instance with `-nativeApprovalPreview instruction-failure`, `reconnecting`, or `reduced-motion`
to fail the first instruction and retry it, check unavailable controls, or check the ring without its sweep. They apply
only to the experimental approval view and never change system accessibility settings. Omit the
argument to return to the normal path. An accessibility `press` on Hold to Allow exercises its
two-step confirmation; `key cmd+y --hold 0.3` exercises early release.

`scripts/tests/ask-window.sh <instance> light <evidence-directory>` opens nine long choices through
an offline ACP fixture, verifies Fine print is showing, compares the window frame, scrolls to the
last choice and checks the delivered answer. Use a dedicated instance: the harness resets its data.
Build and quit that instance first. Repeat with `dark`;
the optional fourth argument selects `confirmation` or `approval`, and a fifth `keyboard` selects
the ninth question choice with its digit key and submits with Return. The harness writes only that
instance's projects, plugin and Labs setting, quits it on exit, and refuses UI checks while locked.
Screenshots, the source revision and diff, the accessibility tree and before/after frames go in the
evidence directory. Its plugin and store are in `/private/tmp/native-ask-window-<instance>`;
its empty project is `.build/ask-window-fixture` in the worktree.
Use `ASK_WINDOW_HEIGHT=620` to stress a shorter window; `failure` as the fourth argument checks a
long failed-start diagnostic, expanded output and Retry. The question check also asserts that the
last choice's accessibility frame lies inside both its scroll viewport and the window.

`<text>` matches an accessibility identifier first, then a title or label exactly, then ignoring
case, then as part of any label, value or help text. Few elements in Native have identifiers of their
own (an icon-only button's is its symbol name, like `#gearshape`), so labels are what you'll use.
When several elements match equally the first in reading order wins and the driver says so on
stderr; `find` shows the order and `--nth` picks another. `--role button` narrows to a role. Every
command exits non-zero with a reason when it can't do what it was asked, so a recipe stops at the
first surprise.

### Recipes

The labels below are the ones Native uses today; when one changes, `find` finds its new name. `D`
stands for `scripts/dev/drive.sh playtest`.

```sh
# A new task: from Home's agent cards, a project's "+" (last-used agent), ⌘N, or any agent by name
$D press "New Claude Code task"
$D press "New Task in sample"
$D menu File "New Task"
$D press "New Task With" --item "Fake Agent"

# Type and send, then wait for the turn to end and read it
$D set Message "Fix the failing test. Don't build or run the app."
$D key return                                   # or: $D press "Send Message"
$D wait "Stop Agent" --gone --timeout 300
$D text                                         # the transcript, as text
$D shot ~/Library/Caches/NativeDevShots/playtest/after-turn.png

# While a turn runs: Return steers it, ⌘Return queues (Settings can swap them)
$D set Message "Then run the tests again." && $D key cmd+return
$D wait "Queued messages" --gone --timeout 300  # the queue drains when the turn ends

# Approve or reject what the agent asks (⌘Y / ⌘⇧⌫ can't be driven, see below)
$D press Allow
$D press Reject

# Stop a turn (Task ▸ Stop and ⌘. need the app active, see below)
$D press "Stop Agent"

# Switch tasks
$D key cmd+1 ; $D key ctrl+tab ; $D key "cmd+["
$D press "Run Tests and Fix Failures"           # a sidebar task, by its title

# Review and commit what the turn changed
$D press "Show Changes"                         # the changes inspector (⌘⇧D)
$D press Review --role button                   # the turn's "files changed" card
$D press Commit --role button                   # opens the commit form under the button
$D set "Commit message" "docs: say where the playtest guide is"
$D press Commit --nth 1                         # the form's own Commit

# Model, effort, autonomy and mode, from the composer's pills
$D press "Model:"                               # opens the model popover (models, effort, fast mode)
$D press "6 Luna"                               # picks a model in it; $D key escape closes it
$D tree | grep -A1 "Reasoning effort"           # in it, the effort control is named for the current effort
$D press Xhigh --role menubutton --item High
$D press "Mode:" && $D press Plan               # Build, Plan, Ask, Debug, Review
$D press "Autonomy:"

# Extra agent settings are in More at every width, with the selected choice checked
$D press "More Controls"                        # lists settings such as Claude Code's Agent selector

# Archive, undo, unarchive
$D key shift+cmd+a && $D press Undo             # archives the open task; its Undo toast lasts about 5 s
$D press Archived                               # expands the sidebar's Archived section
$D action "Add sentence to contributing" AXShowMenu --item Unarchive

# Settings, in the main window
$D key cmd+,                                    # or: $D press Settings
$D press Appearance                             # a page, by its name in the list

# Stop the instance and its host, then relaunch
scripts/dev/run-isolated.sh playtest --quit
scripts/dev/run-isolated.sh playtest --no-build
```

### Things that trip people up

- **Some shortcuts and menu items can't be driven.** Your instance is never the active app (that would
  mean bringing it forward), and `key` still reaches it: typing and Return, Escape and arrows go to
  the focused element (`focused` shows which), and menu items that don't depend on focus work by
  menu or shortcut (⌘K, ⌘N, ⌘1, ⌃Tab, ⇧⌘A, ⌘,). Two kinds need the active app: shortcuts a view
  handles itself (⌘Y and ⌘⇧⌫ on approvals, ⌘Return in popovers and sheets), and Task menu items
  that act on the focused task (Stop ⌘., Focus Composer, Choose Model, Mode, Set Goal), which read as
  disabled. Use the on-screen controls instead (Stop Agent, the composer's pills, Allow), and don't
  report these as broken from the driver; list them as "not verifiable by driver" when they matter.
- **Menus take the person's mouse and keys.** An open menu captures input from whoever is at the Mac,
  so the driver never leaves one open: `press` on a menu button lists the items and closes it, and
  `--item` picks one in the same breath. Prefer `menu` for the menu bar, which never opens anything.
- **Background instances may have no menu bar.** To stop an instance, use
  `scripts/dev/run-isolated.sh <name> --quit`, which also stops its host and agents. When testing
  the quit shortcut or app-only durability, use `drive.sh <name> key cmd+q` to leave the host running.
- **Anything that opens another app or a system panel is out of bounds**: Open In, Sign in, links,
  Add Project and other file pickers. Projects come from `seed`.
- **A covered window isn't redrawn.** `shot` captures the window's own pixels, but parts another
  app's window covers may show what was drawn before they were covered. `windows` and `shot` say
  when the window is covered; place it somewhere uncovered with `frame` or `-nativeWindowFrame`.
  Don't bring it to the front.
- **Accessibility costs the app time.** While a client reads its tree, SwiftUI keeps it current, so
  don't measure performance while driving (`docs/performance.md` has the tools for that), and treat a
  slow `tree` as the driver's cost, not Native's.
- **A quit you didn't cause is a person.** Your instance's window sits on Brayden's screen behind his
  work, and he may click into it, type into it or quit it. If it switches tasks on its own or
  disappears, `drive.sh <name> logs --last 5m` shows `terminate:` for a normal quit: don't relaunch in
  a loop or report it as a bug; wait, and say so in your report.
- **Dialogs hold the app.** Pressing something that opens a modal dialog can report "the app is
  busy"; it worked. `tree` shows the dialog's buttons; `press` one, or `key escape`.
- **Popovers hang off their button.** The commit form, pickers and the like appear in `tree` under the
  button that opened them, so look deeper there (or `find` the field you expect).

## What to look for

[docs/product-quality.md](product-quality.md) is the bar. Hold every screen to it:

- **Every state designed.** After every action: do you know what happened, can you take it back, and
  what's next? An empty list, a missing agent, a failed turn: each says what it is, why, and offers
  the one action that fixes it. Never a blank area, a spinner forever, or a raw error string.
- **One product.** The same situation looks and reads the same everywhere (status, approvals, errors,
  empty states, times and counts). Note any spot that feels like a different app.
- **Failure handled.** When something breaks, Native catches you: says what happened, what it already
  did, and what you can do, with one primary action.
- **Pixel level.** Take screenshots in light and dark (`-appearance.mode`). Look for clipped or
  truncated text, misaligned baselines, uneven padding, jumps and flicker on state changes, wrong
  colors in one appearance, controls that shift when hovered or focused.
- **Keyboard.** [docs/keyboard.md](keyboard.md) is the source of truth: every shortcut there should
  work and be listed in its menu (`drive.sh <name> menu Session` shows the menu's shortcuts), and
  nothing should need the mouse.
- **Feel.** Anything that takes long enough to notice: a send that lags, a sidebar that jumps, a
  transcript that stutters while streaming. Note the time and what you did; don't profile.
- **Crashes and errors.** `drive.sh <name> crashes` after every scenario; `drive.sh <name> logs` for
  errors around the time something went wrong.

## Scenarios

Pick from these, or invent your own the same size. Each is 10 to 30 minutes. Start each from a known
state (seeded, or `--reset` for a first launch) and write down the commit you built.

1. **First launch.** `--reset`, launch, no seed. Can a new person get from nothing to a first answer
   without help? Home with nothing in it, agents listed with their real state (installed, signed in,
   missing). Adding a project opens a folder picker, which is out of bounds: look at everything up to
   it, then quit, seed and relaunch to carry on from a first project and a first task.
2. **Daily coding loop.** In the `native` clone with Claude Code: start a task ("add a line to README.md
   saying where the playtest guide is"), watch it work, approve or review what it asks, read the
   diff, ask for a change, commit it, start the next task. Then the same in `sample` ("fix the
   failing test"). This is the one that matters most: is it faster and calmer than a terminal?
3. **Many tasks at once.** Four or more tasks across both projects (Fake Agent's `slow 40` keeps one
   busy for free): switching between them with the sidebar and ⌘1-⌘9 and ⌃Tab, the sidebar's
   status while several run, Needs you, notifications, archiving and undo.
4. **Long sessions.** A long transcript (the long-session agent, or many turns of `sample` work):
   scrolling back, search (⇧⌘F), jump to latest, following a streaming reply, memory and feel after
   an hour.
5. **Failures.** One at a time, with [failures on cue](#failures-on-cue): agent crashes mid-turn,
   network error, agent not installed, signed out, the project folder deleted or moved, a turn that
   won't stop, the host killed.
6. **Durability.** Start a turn (`slow 60` on Fake Agent, or a real one), then quit the app with ⌘Q
   (`drive.sh <name> key cmd+q`) and relaunch: is the turn still going, and does Native say what
   happened while it was closed? Then the same with the host killed, and with Quit Native and Stop
   Agents.
7. **Settings sweep.** Every Settings page (⌘,): each control does what it says, takes effect without
   a relaunch (or says it needs one), survives a relaunch, and Undo works where offered. Search
   Settings for a few things a person would look for.
8. **Keyboard only.** A whole daily loop without `press`: menus, shortcuts from docs/keyboard.md,
   Tab between controls. Note every place you needed the pointer, and list the view-level shortcuts
   the driver couldn't fire (see [above](#things-that-trip-people-up)) for someone to try by hand.

### Failures on cue

Never break the real Mac to test a failure. Each of these breaks only your instance:

| Failure | How |
| --- | --- |
| Agent crashes mid-turn | Fake Agent: send `crash-once hello`. Or with Claude Code mid-turn: `drive.sh <name> processes` shows the instance's process tree; `kill` the `claude-agent-acp` pid under its Native Host |
| Network error | Fake Agent: `flaky-once hello` fails the first time with a network error |
| A turn that won't stop | Fake Agent: `stubborn 40`, then Stop |
| A long turn | Fake Agent: `slow 40` streams 40 ticks, 300 ms apart |
| Tool approval | Fake Agent: `permission` asks to approve a tool call; Claude Code in a stricter permission mode (⌘⇧M), like Manual, asks too |
| A question for the user | Fake Agent: `question` |
| Agent not installed | Add a plugin whose command doesn't exist (below), relaunch |
| Signed out | A Codex variant with an empty `CODEX_HOME` (below). Don't press Sign in: it opens a browser |
| Project folder gone | `mv /private/tmp/native-playtest/<name>/sample{,-gone}` while Native runs; move it back after |
| Host killed | `kill -9` the Native Host pid from `drive.sh <name> processes`; launchd restarts it |
| Disk or git trouble | In the clone: a merge conflict, a detached HEAD, a branch the origin rejects (`git -C …/origin.git config receive.denyNonFastForwards true`) |

The two extra plugins, written into the seeded plugins folder before a launch:

```sh
plugins=/private/tmp/native-playtest/playtest/plugins
mkdir -p "$plugins/missing" "$plugins/signed-out" /private/tmp/native-playtest/playtest/codex-home
printf '%s\n' '{"id":"playtest-missing","name":"Missing Agent","agents":[{"id":"missing","name":"Missing Agent","command":"playtest-agent-that-is-not-installed"}]}' >"$plugins/missing/plugin.json"
printf '%s\n' '{"id":"playtest-signed-out","name":"Codex Signed Out","agents":[{"id":"codex-signed-out","name":"Codex Signed Out","command":"npx","args":["--yes","@agentclientprotocol/codex-acp@2.2.2"],"resolveExecutables":{"CODEX_PATH":"codex"},"env":{"CODEX_HOME":"/private/tmp/native-playtest/playtest/codex-home"}}]}' >"$plugins/signed-out/plugin.json"
```

Fake Agent answers anything else with `echo: <text>`. Its sessions are listed with `/` as their
folder, so after a relaunch they may not show under the project they started in: that's the fake,
not Native.

## Report an issue

One issue per report, in this shape, sent to whoever asked for the playtest:

```
Title: <what's wrong, in the user's words: "Stop leaves the composer disabled after a stubborn turn">
Severity: blocker | major | minor | polish
  blocker: loses work or stops the daily loop; major: daily friction with a workaround;
  minor: noticeable, rare or cosmetic in a busy place; polish: pixel-level
Build: <commit you built, `git log -1 --format=%h`>, Debug, instance <name>, light/dark, window size
Steps: numbered, from a known state (seeded / reset), with the drive.sh commands you ran
Expected: what docs/product-quality.md or docs/keyboard.md says should happen
Actual: what happened, quoting any text exactly
Screenshot: /path/to/shot.png (before and after when it's a change)
Reproduces: always | N of M tries | once; and whether it does in a fresh instance
Logs: the relevant `drive.sh <name> logs` lines or crash report path, if any
```

Rank what you send by how much it would stop Brayden using Native every day. Keep screenshots in a
folder of your own outside the repo (`~/Library/Caches/NativeDevShots/<name>/`), and never
screenshot anything but your instance's window.

## Clean up

```sh
scripts/dev/run-isolated.sh playtest --quit      # after each check
scripts/dev/drive.sh playtest seed --remove      # the scratch clone, sample repo and plugins
scripts/dev/run-isolated.sh playtest --remove    # settings, data, host, worktrees and the 6 GB build
```

### New Tasks sources (Plainly slice 2)

Enable `experiment.NativeSettingsPlainly` in the isolated defaults. `-newTasksFixture populated`,
`managed`, `empty`, or `unavailable` renders inert agent choices and load inventory on New Tasks.
The managed fixture also needs simulated policy keys (`policy.debug.managedKeys`) for
`policy.permissions.forbiddenModes`, `policy.organization.name`, and `policy.organization.contact`.
Use `auto` as the forbidden fixture choice, Northwind Federal IT and #it-help as the identity.
Fixtures do not start an agent or probe servers. Omit the argument for persistence and real-library
checks. Check both scope menus, each source button, Why This Value, Reset, Undo and project/global
isolation; an unavailable saved model must show the effective agent value and explain the fallback.
