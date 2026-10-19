# Performance

Native runs all day next to the user's editor and terminal, so it has to be slim: launch feels
instant, an idle app costs nothing (no CPU, no wakeups, no battery), and memory stays flat however
long it runs. This document is the budget, how to measure against it, and what the measurements
showed. `just perf` reruns the key numbers. What Native costs to download and install has its own
budget, enforced on every pull request: `docs/app-size.md`.

## Budgets

Measured with `just perf` in a Debug build unless it says otherwise. On a busy Mac (a dozen
agents compiling) wall-clock launch times swing by hundreds of milliseconds, so launch also has a
CPU budget, which doesn't.

Frames are budgeted for 120 Hz, the refresh rate of ProMotion displays (MacBook Pro, iPad Pro,
iPhone Pro): 8.3 ms a frame. On a 60 Hz display the same work has 16.7 ms, which is the floor:
anything that misses that misses everywhere.

| What | Budget |
| --- | --- |
| Launch, warm, to the first frame | under 350 ms on an idle Mac (half a Dock bounce), and under 150 ms of main-thread CPU |
| Launch, to `appInit` | under 60 ms |
| An agent ready to take a session | under 1 s after it's needed (the adapter's own start, plus Native's login-shell read once) |
| Idle, window visible, nothing working | about 0% CPU (under 0.1%), under 1 wakeup per second |
| Idle, minimized or hidden | under 0.05% CPU, under 0.5 wakeups per second; nothing animates, nothing polls |
| Memory, typical workspace (a few tasks, one long transcript open) | Native itself under 150 MB footprint; one adapter process per running agent (no npm wrapper) |
| Sessions nobody uses | released, here and in the agent, once that's possible without losing anything (see "Still to do") |
| Streaming a long reply | main thread under 25% busy, in a long session as in a new one; no frame over 8.3 ms (16.7 ms on 60 Hz displays); footprint back within 20 MB of where it started once the session is left |
| Scrolling a long transcript (500 turns) | no frame over 8.3 ms at reading speed (2,000 points a second) and hardly any in a fast flick (5,000), 16.7 ms on 60 Hz displays; footprint flat (within 20 MB) from the second pass over the whole transcript on |
| Reopening a long session (500 turns) | under 5 s in Debug, the transcript laid out once rather than on every replayed update |
| Animations | Core Animation, never a SwiftUI animation that doesn't stop: motion at up to 120 Hz (`CAFrameRateRange.dsMotion`), ambient loops at 30 Hz (`.dsAmbient`), and nothing while the window can't be seen |
| Growth and leaks | under 10 MB after 30 task switches and 10 Settings toggles; `leaks` finds 0 |
| Changes inspector, any number of files | the list adds under 100 ms of main-thread time to opening it; scrolling under 8.3 ms per frame (120 Hz); a typical file's diff in under 50 ms, big ones collapsed behind Load Diff; at most one rescan a second while an agent writes |

## Measuring

Always in an isolated instance (`scripts/dev/run-isolated.sh perf`), never a copy someone is
using, and quit it afterwards (`just quit perf`). Debug builds are what the instance runs; Release
is faster, so a Debug number inside the budget is a Release number well inside it.

`just perf` (`scripts/perf/measure.sh`) builds the instance, launches it five times and prints the
launch milestones, then leaves the last launch idle and samples it with the window visible,
minimized and hidden, and lists the processes under it. Options: `--no-build`, `--launches N`,
`--seconds S` (each idle sample, default 30), `--settle S` (wait before sampling, default 20).

| Tool | What it gives | Notes |
| --- | --- | --- |
| `scripts/perf/rusage.swift` | CPU %, idle and interrupt wakeups per second, energy (mW), physical footprint, for one process or a process tree, over an interval | Kernel counters (`proc_pid_rusage`), so no sudo. Idle wakeups are what Activity Monitor shows; footprint is its Memory column |
| `scripts/perf/drive.swift` | Presses menu items, writes and sends a prompt, minimizes, hides | Accessibility API, scoped to one pid: no keystrokes, nothing comes to the front |
| `LaunchMetrics` signposts | `launch appInit/firstFrame/sidebarInteractive/agentsReady <ms> ms` in the log, and Points of Interest in Instruments | Milliseconds from the moment the kernel started the process |
| `footprint <pid>`, `vmmap --summary <pid>` | Memory by category | `footprint` is the number macOS uses for memory pressure |
| `leaks <pid>` | Leaked allocations and retain cycles | Run after a workload, compare to a fresh launch |
| `sample <pid> 10` | Where the main thread spends its time | Quick; `xctrace` for more |
| `xctrace record --template 'Time Profiler' --attach <pid> --time-limit 30s` | Time profile | Also `Allocations`, `Leaks`, `Animation Hitches`. Open the `.trace` in Instruments. Always give a time limit and stop it with Ctrl-C (SIGINT), never `kill -9` or `timeout`: its `DTServiceHub` keeps recording without it, tens of GB a minute into `$TMPDIR/instruments*.ktrace` (`lsof` shows who holds one). Delete traces once read |
| `-framePacing YES` (`FramePacing`) | Once a second in the log (`Native`/`Frames`): the display's refreshes, how many the main thread missed, in how many stalls, and the longest | A display link on the main run loop, so it sees exactly the frames the app couldn't make. Costs nothing measurable and writes nothing, unlike an Animation Hitches recording, which here slowed a 12 s scroll to 46 s. Read it with `log stream --predicate 'subsystem == "Native" AND category == "Frames"'` |
| `scripts/perf/scroll.swift` | Scrolls the transcript from one pid: at a speed, or the whole length and back | Sets the scroll bar through Accessibility 120 times a second, so no events reach whatever is under the real cursor. Keeping SwiftUI's accessibility tree current costs the app 10–20% on top |
| `scripts/perf/long-session-agent.py` | A fake agent with sessions of 20, 100 and 500 turns to reopen, and a long reply streamed on request | `--install <folder>` writes its plugin; launch with `-pluginsDirectory <folder>` |

`powermetrics` needs sudo, so energy comes from `ri_energy_nj` (the same counter Activity Monitor's
Energy Impact is built on) instead.

### Launch milestones

`native/Performance/LaunchMetrics.swift` marks each milestone once, measured from the process's
start time (`kinfo_proc.p_starttime`), which is as close to the Dock click as an app can see:

| Milestone | Means |
| --- | --- |
| `appInit` | `NativeApp.init` runs: dyld and static initializers are done |
| `firstFrame` | The main window's first frame is committed and the main thread is idle |
| `sidebarInteractive` | The sidebar's rows are on screen and the main thread can take a click |
| `agentsReady` | Agents are checked and the default one is running, so New Session doesn't wait |

The first three are what "instant" means. `agentsReady` happens off the main thread and is only
there to catch regressions in agent startup.

"Cold" without sudo can't purge the file cache, so the first launch after a build stands in for it
(new binary, dyld closure not cached); the other launches are warm.

### By hand

- **Sessions.** `drive <pid> menu File "New Session"`, then `drive <pid> prompt "…"`; `drive <pid>
  enabled Session Stop` says whether a turn is still running.
- **Streaming.** Start a long Codex turn (`gpt-6.1-sol`, which the instance uses), then
  `sample <pid> 20` for the main thread and `rusage` for CPU and footprint growth.
- **Growth and leaks.** Note `footprint`, run the workload (open and archive 20 sessions, switch
  tasks, toggle Settings, the terminal and the inspectors), note it again and run `leaks <pid>`.

## Results

2026-10-18, Debug build in the `perf` instance, Codex (`gpt-6.1-sol`) as the default agent, one
scratch project. The Mac was very busy (load average 150 to 220 on 16 cores, other agents
compiling), so wall-clock launch numbers are high and noisy; compare the CPU columns. "After" is
the tree a few hours later, which also has the features that landed in between (search over agent
history, telemetry, the command palette), so not every difference is this work's.

### Before and after

| Measurement | Before | After |
| --- | --- | --- |
| Launch, warm: `appInit` | 44–66 ms | 56–61 ms |
| Launch, warm: first frame (wall, busy Mac) | 702–1308 ms | 533–534 ms with agent-history search off; 838–976 ms with it on |
| Launch, warm: main-thread CPU to first frame | not measured (added with this work) | 332–352 ms main, 481–486 ms process, search off (402–428 before the plugin-scan fix; 585–716 with search on) |
| Launch: agents ready (`agentsReady`) | 2471–4242 ms | 892–914 ms |
| Codex adapter start to `initialize` answered | 1085–2185 ms through npx | 287–306 ms direct |
| Claude adapter start to `initialize` answered | 4018 ms through npx | 1332 ms direct |
| Idle, visible, no sessions: Native | 0.07% CPU, 0.6 wakeups/s, 111 MB | 0.02% CPU, 0.4 wakeups/s, 115 MB |
| Idle, minimized / hidden: Native | 0.01% CPU, 0.7 / 0.3 wakeups/s | 0.01% / 0.05% CPU, 0.4 / 0.4 wakeups/s |
| Idle, no sessions: processes under Native | 4, 295 MB footprint (npm wrapper 69 MB) | 3, 205–233 MB |
| Idle, 1 session: Native / everything under it | 0.22% CPU, 0.9 wakeups/s, 94 MB / 14 processes, 990 MB | 0.02% CPU, 0.7 wakeups/s, 127 MB / 13 processes, 1.31 GB |
| Idle, 5 sessions: Native / everything under it | 0.30% CPU, 99 MB / 54 processes, 5.26 GB | 0.42% CPU, 134 MB / 53 processes, 5.29 GB; closing idle sessions doesn't change it yet (below) |
| Streaming a 2,500-word reply: Native CPU | 36.7% over 25 s, 88 wakeups/s, 91 mW | 24.5% over a 45 s turn, 67 wakeups/s, 85 mW (measured without a profiler attached; the "before" ran under `sample`, which inflates both) |
| Streaming: main-thread time in Keep Awake | 338 ms per 25 s (a power-source IPC per chunk) | 0 (only when the working count changes) |
| Streaming: footprint | 104 MB → 364 MB (225 MB of it graphics), 138 MB after leaving the session | 193 MB → 420 MB, again mostly graphics, held while a long reply is on screen |
| 30 task switches + 10 Settings toggles | +6 MB, 0 leaks | +12 MB; 297 leaks (20 KB) at launch, 5,532 (268 KB) after, all inside the Metal driver (IOGPUMetalBuffer and AGXHeap descriptors), none in Native |

### What the measurements showed

- **Every open Codex session holds the user's MCP servers.** Codex starts each configured MCP server
  for every session it has open (here two of each: one through npx, and a computer-use helper),
  about 1 GB per session with this Mac's config. Native never closed a session, so five
  tasks opened once held 54 processes and 5.26 GB until the agent stopped, and the default agent
  never stops. Native can now close sessions nobody has used for a while (`session/close`, which
  codex-acp and claude-agent-acp both support) and drop their transcripts; selecting one loads it
  back. It's off by default (the `sessionIdleTimeout` default, in seconds, turns it on) because
  in testing it didn't pay, and at first reopening wasn't faithful:
  - Closed Codex sessions kept their MCP servers: 11 minutes later they were still running. Codex
    unloads a closed thread after `thread_unload_delay_secs` (60 s by default), but codex-acp never
    unsubscribes the title-generation thread it starts for each session, so that thread's MCP
    servers live until the adapter exits (codex-acp#628, fixed by the open #629). Setting the delay
    through `CODEX_CONFIG` wouldn't help either: codex-acp applies it per thread, where the
    app-server ignores it.
  - A session loaded back showed its transcript correctly, but codex-acp 2.2.2 reopens it on its
    default model and mode (6 Astra and Auto review instead of the 6.1 Sol and Full access it ran
    with), and the same happened whenever an agent restarted. Native now remembers the settings
    chosen for each session (`ConfigChoices`, kept by `SessionTitles`) and sets them back after
    `session/load`, before anything queued goes out (`SessionModel+ConfigRestore.swift`). The
    title was never the agent's: Native's own wins on load too, and the on-device titler had
    named that session "Reply with OK2" itself.
- **npx sat between Native and every adapter.** `npx --yes <adapter>@<version>` keeps an
  `npm exec` Node process alive as the adapter's parent (52–118 MB each) and adds 0.8–2.7 s to
  every agent start. When npx has already installed that exact version, Native now runs the
  installed binary itself (`AgentCommand.skippingNpx()`), with the `PATH` npx would give it.
- **Keep Awake asked the power source on every streamed chunk.** It follows the number of working
  tasks, which is re-read on every change; each re-read re-ran the engine, which calls
  `IOPSCopyPowerSourcesByType` (an IPC to powerd). Now only a changed count reaches the engine.
- **The hang watchdog woke the app every second.** It pinged the main thread from a background
  task forever, hidden or not. It now watches the main run loop instead: the same two-second
  rule, no wakeups.
- **Polling while hidden.** The GitHub refresh loop woke every 5 s to compare dates, and the
  status bar's resource sampling checked visibility every 3 s while hidden. Both now sleep until
  something changes (the next due refresh, coming back to the app, the app becoming visible).
- **Terminals kept drawing when the window wasn't visible.** libghostty was only told a surface
  was hidden when its view left the window; it's now also told when the window is minimized,
  hidden or covered.
- **The Markdown cache could hold a long reply hundreds of times.** It keyed parses by source and
  capped the count at 512, but every streamed chunk is a new source holding the whole reply so
  far. It now also caps the total source size at 4 MB.
- **Plugin manifests were rescanned on every read.** `PluginRegistry.plugins` re-applied
  experiments on every access, and finding out whether a manifest uses any ran a regex over every
  agent argument and environment value. That's most of what the idle loop's once-a-minute tick
  cost. Each loaded plugin now works that out once.
- **Search over agent history reads the whole history at every launch.** With search on, the
  first minutes after launch ran at 15–45% CPU, hidden or not, with footprint up to 370 MB,
  parsing every Claude Code JSONL file; it also adds about 300 ms of main-thread CPU before the
  first frame.
- **Launch is mostly the main thread.** It spends about 0.4 s of CPU before the first frame in
  this Debug build (0.6–0.7 s with agent-history search on), against a 150 ms budget. The biggest app-side pieces in the time profile: plugin manifests rescanned
  for experiment placeholders (a regex over every argument) on every `PluginRegistry.plugins`
  read, the MCP config files parsed on the main thread (`~/.claude.json` is 315 KB here), and
  the home card grid's layout. The rest is SwiftUI and AppKit building the window, plus waiting on
  system services (LaunchServices check-in, preferences, window restoration), which a busy Mac
  slows down.
- **Idle with the window visible was already close to zero.** No animation or clock runs when
  nothing works: `TimelineView`s stop with their views, and loaders only show for working tasks.

- **The agent-history backfill is incremental.** Per-file checkpoints (size, modification time and
  the byte offset already indexed) skip unchanged files and resume grown ones; files stream a
  megabyte at a time; the first fill runs at utility priority on power, later passes at background
  priority; nothing runs before the first frame. A launch with nothing new to index now costs no
  main-thread time before the first frame (333-374 ms, the same as search off) and about 0.1 s of
  extra CPU, down from 15-45% for minutes, and the footprint stays at 88-93 MB instead of up to
  370 MB. Details in docs/search.md, Performance.

### New sessions on a large repository

2026-10-19, Debug build in an isolated instance, Codex (`gpt-6.1-sol`), a shallow clone of the
Linux kernel (96,080 files, 2 GB checked out) with 20,000 remote branches, a `.env` and an ignored
folder of 2,000 files; worktree mode. The Mac was busy (load average 7 to 40). "Usable" is the
composer taking typing in the new task.

| Measurement | Before | After |
| --- | --- | --- |
| "+" to visible feedback in the sidebar | none until the session existed (18.2 s); the empty project read "Add an agent to start a session" meanwhile | 84-123 ms: a "Starting…" task, selected, saying what it waits for |
| "+" to a usable composer | 18.2 s | 89-146 ms; a message sent then goes out when the session exists |
| "+" to the session open (agent ready for the first message) | 18.2 s | 10.5 s (13.5 s at load average 47) |
| `git worktree add` alone | 20.5-22.0 s | 10.1-11.0 s (`checkout.workers=0`) |
| A second "+" while the first was starting | dropped silently | a second starting task, queued behind the first's git work |
| Main thread while the worktree is made | idle (git runs in its own process) | idle |

- **The click waited for everything before showing anything.** New Session made the worktree,
  waited for the agent and asked for the session before the task existed anywhere on screen, and
  ignored any other New Session meanwhile ("one at a time"). Now the click adds a starting task to
  the sidebar and selects it at once (`AppModel+StartingTasks.swift`): its composer takes the first
  message, which goes out when the session exists, and the worktree and the agent start at the same
  time. A failure stays on the task with Retry and Discard instead of an alert.
- **Git checked a new worktree out one file at a time.** `git worktree add` now runs with a checkout
  worker per core (`Repository.parallelCheckout`), which halves it on this repository. Sparse and
  `--no-checkout` worktrees were ruled out: the agent has to see the whole project from its first
  turn. Cloning the main checkout's files (APFS clones) was measured too and lost: populating took
  9 s and refreshing the index another 18 s.
- **Nothing scans the repository on the main thread.** The worktree, the env-file copy
  (`git ls-files --ignored`, 0.35 s here), the status scan of the new worktree (0.4-0.8 s) and the
  file list for `@` mentions (only when one is typed) all run in git's own processes or off the
  main actor; `sample` shows the main thread idle throughout.

### Streaming

2026-10-18, evening, Debug build in an isolated instance with about 30 sessions in the sidebar
(load average 6 to 15). A fake ACP agent streamed the same reply every time: 24 sections of prose,
a list and a code block each, about 18,000 characters, 4 to 30 characters every 45 ms, which is
about Codex's pace. CPU is over 15 s of streaming with nothing attached; the main thread's share
comes from a 10 s `sample` right after. "Before" is the build from the start of the day.

| Measurement | Before | After |
| --- | --- | --- |
| A turn with no output yet (the agent thinking, tools running) | 43–58% CPU, 33–66% main thread, +225–257 MB graphics | 0.05% CPU, under 1% main thread, no graphics |
| Streaming the reply | 100–107% CPU, main thread 100% busy | 22–25% CPU, main thread 24–29% busy |
| Streaming: footprint | 210 MB → 477–484 MB peak | 173–187 MB → 184–213 MB peak, 172–190 MB after leaving the session |
| Codex (`gpt-6.1-sol`), a 2,500-word reply with eight code blocks: main thread | 77% busy | 17% busy (one run each; Codex's pace varies) |
| A thought running ("Thinking…" shimmer) | 34–38% CPU, 31–33% main thread | 0.9–1.1% CPU, about 1% main thread (the elapsed time ticking each second) |
| Home on Nightly (the night sky) | 18.6% CPU, +257 MB graphics, for as long as Home shows | 0.02% CPU, no graphics |
| Re-renders over a Codex reply's 169 chunks | `ComposerView` 340, `ModelPill` 453, `SessionRow` 2,921 | 2, 11 and 309 (two bursts at session events, none per chunk) |
| Code blocks left without colors (Codex, the same six-block reply) | 4 of 12 replies | none in 6 replies, and no block drops its colors mid-stream |

- **Animations that never stop re-rendered the window every frame.** The dot-grid loaders, the
  shimmer over "Thinking…" and running tools, and Nightly's night sky animated with
  `TimelineView(.animation)`, and every frame of a SwiftUI animation that never stops runs an
  update of the whole window's view graph and redraws the window: that's the 225 MB of graphics
  the first measurements blamed on the growing reply, and most of the streaming CPU. A standalone
  SwiftUI window with one such loader does the same (257 MB). All three now animate in the render
  server instead (`LayerMaskedView`): SwiftUI draws the content once (a fill in the foreground
  style, or the busy text in the primary color) and a Core Animation mask moves over it: the
  pulsing dots, the sweeping band, the twinkling stars and drifting bats. On the Mac the masks
  pause while the window is hidden, minimized or covered.
- **The window measured the transcript at no width on every update.** AppKit asks the window's
  content for its minimum size whenever it changes, and SwiftUI lays the content out at zero width
  to answer, the transcript included: every line of the reply wrapped a character at a time, on
  every chunk. The transcript is now an overlay sized by the space it's given.
  The same measurement can crash the app: text that keeps its full height
  (`.fixedSize(horizontal: false, vertical: true)`) in window content outside a scroll view, an
  overlay or a fixed-width sheet or popover reports its height at no width, one character a line,
  as the window's minimum. Each change grows the window until AppKit aborts the layout pass ("more
  Update Constraints in Window passes than there are views"); a task-scripts banner did this. The
  main window's columns are now measured at least `DS.Window.sidebarMinWidth` and
  `DS.Window.detailMinWidth` wide (`platformMinimumContentWidth`), and the rule is: in window
  content, let text wrap from the width it's given, and give `fixedSize` only to text with a
  bounded width (a fixed frame, a line limit) or inside a scroll view.
- **The composer, sidebar rows, status bar and menus read `session.state`.** `needsApproval` and
  `wait` scanned the transcript for permission requests, and the composer read the plan, slash
  commands and settings from `state`, so all of them re-rendered on every chunk, `RootView` and
  the menu commands included. `SessionModel` now mirrors those parts of `state` and writes a mirror
  only when it changes.
- **A reply re-parsed whole on every chunk.** Markdown now splits at top-level block boundaries
  (`String.markdownSections`), each section parses and renders on its own, and the standard
  transcript shows a reply's sections as rows of their own, so a chunk only re-parses and lays
  out the last one.
- **Code blocks could stay plain for good.** A block streaming many times a second can miss its
  `.task(id:)` restarts (and `onChange`) altogether, the last one included, so its final text was
  never highlighted. `LiveCodeHighlighter` is driven by rendering instead: a render of text without
  colors makes sure it's highlighted, at most every 100 ms while it changes, keeping the colors
  of the part that didn't change meanwhile.

### Changes inspector

2026-10-19, Debug build in an isolated instance on scratch repositories: 250 changes (275 rows:
modified, deleted, renamed, staged, partly staged, binary and untracked files across 150 folders,
ten of them 200–480 KB with hundreds of changed lines) and the same mix at 1,000 changes (1,100
rows). The Mac was busy (load average 20 to 90), so each figure is a range over three or four runs.
Main-thread time is the main thread's CPU time (`proc_pidinfo`), sampled every half millisecond
after one Accessibility press of the toolbar button or a row. Scrolling steps the list's scroll bar
through Accessibility, about 23 points at 120 Hz. Driving the app through Accessibility keeps
SwiftUI's accessibility tree up to date, which both columns pay (15–30% of the work in the profiles).

| Measurement | Before | After |
| --- | --- | --- |
| Opening, 250 files: main-thread time | 670–1,140 ms, mostly one 480–700 ms stall | 150–550 ms; opening it on a clean repository costs 220–295 ms |
| Opening, 1,000 files | 1.4–2.6 s, busy for over 3 s | 395–577 ms |
| Scrolling, 250 files: main-thread time per step | about 16 ms, and it fell behind (158 of 360 steps) | 4.4 ms, every step |
| Scrolling, 1,000 files | about 76 ms per step | 3–7 ms per step |
| Selecting a small file | 190–375 ms | 115–165 ms |
| Selecting a 243 KB file with 575 changed lines | 8.6 s of main-thread time over 10 s; the diff appeared after more than 4 s; selecting another file then took 2.6 s | 58 ms to a "Large diff" notice; Load Diff 129 ms; selecting another file 176 ms |
| A first scan of 1,000 changed files | the list waited for every file's line counts (about 450 ms of git here) | the list shows after `git status` (20–90 ms); the counts follow |
| An agent writing 3 files every 100 ms for 10 s | not measured | 4 scans, 85–153 ms of main-thread time in all |

- **The list wasn't lazy.** It was a `LazyVStack` of sections, but each section was a plain
  `VStack` of all its rows, so the stack's one child per section measured every row before the
  first frame: 90% of opening in the profile. Every row is now a child of the lazy stack
  (`Section` inside it), so only the rows on screen are built and measured. Opening on a clean
  repository costs nearly as much as on 250 files now; the rest is the inspector column animating
  open, which lays the whole window out each frame.
- **Rows built buttons nobody saw, and any change rebuilt every row.** Each row built its stage
  and discard buttons hidden, and took closures, which SwiftUI can't compare, so a selection,
  a diff arriving or a rescan re-ran every row. Rows now build their buttons only while they
  show, act through the model, and are skipped when their file didn't change; the diff pane reads
  the selection itself, so a diff arriving redraws only the pane. A change's id is a small struct
  instead of a string interpolated through reflection on every comparison.
- **Diffs were computed on the main thread, more than once.** Selecting a file diffed it on the
  main thread to count its lines, and `DiffView` diffed it again in every body evaluation, then
  laid out up to 400 rows at once. The diff is now read and laid out off the main thread
  (`GitDiffContent.load`, `DiffLayout`), its rows are built as they scroll into view, and a
  change past 96 KB or 600 changed lines waits behind Load Diff. Both sides of a file are read at
  the same time.
- **The first scan waited for the line counts.** The list now shows from `git status` alone and
  the counts stream in; later scans keep the old counts on screen until the new ones arrive. With
  nothing staged, git diffs the working tree once instead of twice for the totals.
- **Rescans ran back to back while an agent wrote.** Events arriving during a scan queued another
  right after it, every event batch ran `git check-ignore`, and each finished tool call asked for
  an immediate rescan on top of the file watcher's. While events keep coming, scans now run at most
  once a second, batches that a pending scan will cover skip the ignore check, and tool calls wait
  for the same settled scan; ending a turn still rescans at once.
- **Rows had no default action.** A row's button trait had nothing to press, so VoiceOver (and
  automation) couldn't select a file. It now selects it.

### Long transcripts

2026-10-19, Debug build in an isolated instance on this Mac's 120 Hz built-in display (M4 Max), with
a dozen agents building alongside (load average 5 to 130, so each figure is a range over runs). A
fake agent (`scripts/perf/long-session-agent.py`) replays a 500-turn session the way Codex's history
looks: about 6,400 items in 9,439 updates (10.8 MB), with prompts, reasoning, commentary, reads,
searches, commands with output, edits with diffs, and Markdown replies with headings, lists, code
blocks and tables. Folded, the transcript is about 290,000 points tall. `scripts/perf/scroll.swift`
scrolls it from the bottom up and back for 12 s; frames come from `-framePacing YES`, the main
thread's profile from `sample`. The view fixes were tried one at a time in a copy of the tree, in one
build switched by a launch argument, then made in the transcript.

| Measurement | Before | After |
| --- | --- | --- |
| Reopening the 500-turn session | not done after 19 min (19 min of CPU, the main thread pinned) | 4.3–6.6 s, 4.6–8.8 s of CPU |
| Reopening the 100-turn one | 58 s | 3.3 s |
| Scrolling at 5,000 points a second (a fast flick) | 45–54% of refreshes drawn, 56–66 dropped a second, worst stall 154–304 ms, 15.5–22.8 s of CPU for 12 s (the main thread always busy, the scroll fell behind) | 67–89% drawn, 13–40 dropped a second, worst stall 75–123 ms, 7.1–11.8 s of CPU |
| Scrolling at 2,000 points a second (reading) | 84% drawn, 20 dropped a second, worst stall 129 ms | 87–93% drawn, 9–16 dropped a second, worst stall 81–139 ms |
| The whole transcript and back in 10 s (every frame all new rows) | not measured | 20–23% drawn; the main thread lays out a screenful of new text each frame |
| Streaming a long reply into the 500-turn session | main thread 99–100% busy, 3% of refreshes drawn, worst stall 2.7 s | 36% drawn, worst stall 565 ms with the reply-sections cache fixed; with the per-turn plan cache as well, 42% CPU and 55% drawn (below). A 20-turn session: 30% CPU, 72–79% drawn |
| Footprint over three passes over the whole transcript | not measured | 169 → 209 → 227 → 224 MB, 371 MB at the peak of a pass |

- **Reopening a session laid the transcript out once per replayed update.** `ACPConnection` hands
  updates over one main-actor hop at a time, so SwiftUI updated the transcript between any two of
  them, and each update planned every turn: it found turns by scanning every item and counted every
  turn's edits by diffing old and new text (`FileDiff.lineCounts`). That made reopening quadratic.
  Now a diff's line counts are worked out once, when it's decoded off the main thread;
  `SessionState` keeps turn starts, turn summaries, pending permissions, subagents and finished
  writes up to date as items change, instead of scanning for them; and `SessionModel` lets the
  transcript hear about replayed history at most every 100 ms and once more when loading ends.
  `SessionModel`'s mirrors no longer pass over the transcript either.
- **Rows weren't one view each.** The standard transcript's `ForEach` built each line from a switch
  whose branches don't always make exactly one view, so the lazy stack couldn't map lines to views
  and walked and built `ForEach` items on every placement pass. That was 70% of the main thread
  while scrolling. Each line is now wrapped in one stack.
- **Every streamed chunk planned every turn again.** In the 500-turn session `plan()` was 74% of
  the main thread while a reply streamed. The cache of reply sections held 512 replies, fewer than
  a long session has, so every plan cleared it and split every reply again (48%). The usage-limit
  check folded the whole of every turn's last reply to compare its first words (11–39%). Grouping
  rows for the whole session took 14%. And the Git refresh counted finished writes over the whole
  transcript (6%). Now the usage-limit check compares the first characters only, Git reads a count
  `SessionModel` keeps, and the transcript keeps each earlier turn's lines until
  `TranscriptTurn.revision` (which moves whenever one of the turn's items changes) says the turn
  changed. Only the turn that's streaming is planned again.
- **The Markdown parse cache held 512 sections**, fewer than a long session has (about 2,500 for
  500 turns), so scrolling back re-parsed. It now holds 8,192, still capped at 4 MB of source.
- **Hover hit-tested every frame.** Rows that highlight on hover made SwiftUI hit-test the view
  tree under the cursor on every frame the content moved (12–19% of a fast scroll). The transcript
  stops taking hits while a scroll gesture is under way. This one wasn't measured: driving the
  scroll bar has no scroll phase, and the real cursor isn't ours to move.
- **The transcript's own changes, measured in the shared tree** (19:15, after everything above
  landed): an external 240 Hz display had become the main one (the probe still counts at 120 Hz) and
  the load average was 135 to 275, ten times the cores, so these only bound the earlier rows. Scrolling
  at 5,000 points a second drew 47% of refreshes with a worst stall of 66 ms, at 2,000 points 80%
  with 71 ms; streaming into the 500-turn session took 42% CPU (100% before) and drew 55% of
  refreshes, with `plan()` down to 27% of the main thread's samples. Most of what's left there is
  SwiftUI reading the id of every line of the `ForEach` on every chunk (19%).
- **What's left is text.** On a pass over the whole transcript, a quarter to a third of the main
  thread lays out selectable text (TextKit 2) for rows coming into view. Lists lay out with a `Grid`
  (4.6–8.3%), every code block hosts a scroll view of its own (3.8%), and keeping the accessibility
  tree current for the driver costs 10–20%, which only a user with an accessibility client pays.
- **120 Hz.** The Core Animation loops ask for the frame rate their motion needs: the shimmer band
  and the loaders' pulsing dots up to 120 Hz, the night sky's twinkling and drifting at 30 Hz. The
  iPhone companion opts in to 120 Hz (`CADisableMinimumFrameDurationOnPhone`).

## Still to do

| What | Why | Owner |
| --- | --- | --- |
| Let Codex unload closed threads | codex-acp never unsubscribes its title-generation thread, so each session's MCP servers (about 1 GB each here) outlive it until the adapter exits | Upstream codex-acp#628 / #629; then turn idle closing on |
| Turn on closing idle sessions | Once the row above is done (reopening is faithful now): default `sessionIdleTimeout` to 10 minutes. Also check claude-agent-acp, where each session is its own Claude Code process | App model |
| Cache the applied plugin list itself | Only the experiment scan is cached; `plugins` still maps every loaded plugin on every read | Experiments / plugins |
| "Couldn't run git: The file “project” doesn't exist" alert | New Session in a project whose folder is gone shows a modal; the sidebar already says "Can't find this project's folder" with Retry | Failures |
| Find what holds memory after a Codex reply | After the first long Codex reply, footprint stayed about 85 MB up (167 MB → 252 MB, mostly Malloc Small) after leaving the session; replies from a fake agent come back within 20 MB | Transcript, app model |
| Read MCP config files off the main thread at launch | About 14 ms in Debug before the first frame; agents can wait for it instead | MCP |
| Park the default agent when it has no open sessions for a long while, or start it on the first New Session | It's kept running so New Session never waits; with direct adapter launch that wait is now about 0.3 s for Codex | App model |
| Open inspectors without laying the window out every frame | Opening the changes inspector costs 220–295 ms of main-thread time even on a clean repository: the column's open animation lays out the whole window, transcript included, each frame | Session view |
| Selecting a file in the changes inspector under 50 ms | Still 115–165 ms in Debug with Accessibility on: the pane draws a loader, then the diff, then again with colors | Git |
| Scroll a long transcript at 120 Hz | Still 7–33% of refreshes dropped in a fast flick and 7–13% at reading speed (Debug): new rows lay out their selectable text on the main thread. Then lists without `Grid`, and code blocks without a scroll view each | Transcript |
| Streaming into a long session within budget | 42% CPU in the 500-turn session against 30% in a 20-turn one: every chunk still has SwiftUI read the id of each of the transcript's thousands of lines (19%), and plans the streaming turn. Measure again on a quiet Mac first | Transcript |
| Release-build numbers for long transcripts | Everything above is Debug; Release is faster, but the lazy stack and text layout are system code either way | Performance |
| Stop re-rendering the session view on every git rescan | `SessionView` reads `repository.summary` and `status` for the subtitle and the Commit action, so each rescan re-runs its body | Session view, Git |
