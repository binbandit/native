# Performance

Native runs all day next to the user's editor and terminal, so it has to be slim: launch feels
instant, an idle app costs nothing (no CPU, no wakeups, no battery), and memory stays flat however
long it runs. This document is the budget, how to measure against it, and what the measurements
showed. `just perf` reruns the key numbers. What Native costs to download and install has its own
budget, enforced on every pull request: `docs/app-size.md`.

## Budgets

Measured with `just perf` in a Debug build unless it says otherwise. On a busy Mac (a dozen
agents compiling) wall-clock launch times swing by hundreds of milliseconds, so launch also has a
CPU budget. CPU time still doubles when the main thread lands on efficiency cores, so launch is
also counted in main-thread instructions, which a busy Mac doesn't change: an idle performance
core runs about 10 M of them a millisecond here, so 150 ms is about 1.5 G.

Frames are budgeted for 120 Hz, the refresh rate of ProMotion displays (MacBook Pro, iPad Pro,
iPhone Pro): 8.3 ms a frame. On a 60 Hz display the same work has 16.7 ms, which is the floor:
anything that misses that misses everywhere.

| What | Budget |
| --- | --- |
| Launch, warm, to the first frame | under 350 ms on an idle Mac (half a Dock bounce), and under 150 ms of main-thread CPU (about 1.5 G main-thread instructions), with 30 tasks in four projects (`just perf --fixture`) |
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
using, and quit it afterwards (`just quit perf`). Debug builds are what the instance runs. Release
runs Native's own code several times faster, but launch is mostly AppKit and SwiftUI building the
window, which is the same code in both: a Release launch does only about 6% less work.

`just perf` (`scripts/perf/measure.sh`) builds the instance, launches it five times and prints the
launch milestones, then leaves the last launch idle and samples it with the window visible,
minimized and hidden, and lists the processes under it. Options: `--no-build`, `--launches N`,
`--seconds S` (each idle sample, default 30), `--settle S` (wait before sampling, default 20),
`--fixture` (launch into four projects, three with icons of their own, and 30 tasks, written again
before every launch by `scripts/perf/fixture.sh`, instead of one empty scratch project; the window
opens at its default size rather than as the last launch left it, since a different size lays out
different rows) and `--launch-only` (stop after the launches).

| Tool | What it gives | Notes |
| --- | --- | --- |
| `scripts/perf/rusage.swift` | CPU %, idle and interrupt wakeups per second, energy (mW), physical footprint and instructions per second, for one process or a process tree, over an interval | Kernel counters (`proc_pid_rusage`), so no sudo. Idle wakeups are what Activity Monitor shows; footprint is its Memory column; instructions don't depend on the core or the load |
| `scripts/perf/drive.swift` | Presses menu items, writes and sends a prompt, minimizes, hides | Accessibility API, scoped to one pid: no keystrokes, nothing comes to the front |
| `LaunchMetrics` signposts | `launch appInit/firstFrame/sidebarInteractive/agentsReady <ms> ms` in the log, with the main thread's and the process's CPU time and the main thread's instructions, and Points of Interest in Instruments | Milliseconds from the moment the kernel started the process |
| `scripts/perf/profile-launch.sh --name <instance> [--fixture]` | A Time Profiler trace of a launch from its first instructions | Opens the instance's own build, stops it at once, attaches, lets it run. Never `xctrace --launch` a Native binary: it can start the installed Native instead. A stopped launch does less of the window's first layout and focus work than a normal one, so take totals from `just perf` |
| `footprint <pid>`, `vmmap --summary <pid>` | Memory by category | `footprint` is the number macOS uses for memory pressure |
| `leaks <pid>` | Leaked allocations and retain cycles | Run after a workload, compare to a fresh launch |
| `sample <pid> 10` | Where the main thread spends its time | Quick; `xctrace` for more |
| `xctrace record --template 'Time Profiler' --attach <pid> --time-limit 30s` | Time profile | Also `Allocations`, `Leaks`, `Animation Hitches`. Open the `.trace` in Instruments. Always give a time limit and stop it with Ctrl-C (SIGINT), never `kill -9` or `timeout`: its `DTServiceHub` keeps recording without it, tens of GB a minute into `$TMPDIR/instruments*.ktrace` (`lsof` shows who holds one). Delete traces once read |
| `-framePacing YES` (`FramePacing`) | Once a second in the log (`Native`/`Frames`): the display's refreshes, how many the main thread missed, in how many stalls, and the longest | A display link on the main run loop, so it sees exactly the frames the app couldn't make. Costs nothing measurable and writes nothing, unlike an Animation Hitches recording, which here slowed a 12 s scroll to 46 s. Read it with `log stream --predicate 'subsystem == "Native" AND category == "Frames"'` |
| `-nativeAutoScroll <seconds>` (`PlatformAutoScroll`, Mac) | Scrolls the window's tallest scroll view by itself once per refresh at 120 Hz, starting that many seconds after a list asks for it (Files Changed does) | No accessibility client attached, which would make SwiftUI update its accessibility tree every frame; pair it with `-framePacing YES`. `-nativeAutoScrollSpeed` (points a second, 6,000), `-nativeAutoScrollDistance` (30,000; negative goes up), `-nativeAutoScrollWheel YES` (wheel events instead of moving the clip view), `-nativeAutoScrollLog <path>` (written when done). Right for top-anchored lists; a bottom-anchored SwiftUI scroll view (the transcript) slides its rows off the end under it and draws nothing new, so use the next row there |
| `-nativeTranscriptAutoScroll <seconds>` (`TranscriptAutoScroll`) | Scrolls the opened session's transcript through SwiftUI itself, a prompt or reply at a time (`-nativeTranscriptAutoScrollRate`, a second; `-nativeTranscriptAutoScrollCount`), up and back | Each step shows a screenful of new rows, so it measures rows coming into view more than smooth scrolling |
| `-nativeOpenSession <agent>/<session id>` (`PerformanceDriver`) | Selects a session at launch once its agent lists it; then `-nativeOpenSessionLog <path>` (written once loaded), `-nativeOpenSessionPrompt <text>` (sent as the user would), `-nativeRevealItemFromEnd <n>` (scrolls there as search does) | `-nativeWindowFrame "x y w h"` moves the window first. Every isolated instance opens in the same place, and a window other windows cover isn't drawn: its frame numbers measure nothing, and screenshots of it show what was drawn before. Check with `CGWindowListCopyWindowInfo` that nothing is above it |
| Optimized builds with the drivers | `xcodebuild -configuration Debug … -derivedDataPath /tmp/native-dd/<name>-release NATIVE_BUNDLE_IDENTIFIER_SUFFIX=.dev.<name> SWIFT_OPTIMIZATION_LEVEL=-O SWIFT_COMPILATION_MODE=wholemodule ENABLE_DEBUG_DYLIB=NO ENABLE_TESTABILITY=NO GCC_OPTIMIZATION_LEVEL=s build` | Never launch a Release build of an instance: its host plist has the standard channel, so it registers a login item and talks to the installed Native's host (`NativeHostHelper/install-launch-agent.sh` gives only Debug a channel of its own). This is the Debug configuration compiled like Release, with a development host per build folder; the drivers and `-framePacing` compile into Debug (and into Release with `NATIVE_PERF`) |
| `scripts/perf/scroll.swift` | Scrolls the transcript from one pid: at a speed, or the whole length and back | Sets the scroll bar through Accessibility. Keeping SwiftUI's accessibility tree current costs the app 10–20% on top, and like `-nativeAutoScroll` it doesn't move a bottom-anchored transcript the way a trackpad does, so its transcript numbers below are withdrawn |
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
| `agentsReady` | Agents are checked and the default one is running, so New Task doesn't wait |

The first three are what "instant" means. `agentsReady` happens off the main thread and is only
there to catch regressions in agent startup.

"Cold" without sudo can't purge the file cache, so the first launch after a build stands in for it
(new binary, dyld closure not cached); the other launches are warm.

### By hand

- **Tasks.** `drive <pid> menu File "New Task"`, then `drive <pid> prompt "…"`; `drive <pid>
  enabled Task Stop` says whether a turn is still running.
- **Streaming.** Start a long Codex turn (`gpt-6.1-sol`, which the instance uses), then
  `sample <pid> 20` for the main thread and `rusage` for CPU and footprint growth.
- **Growth and leaks.** Note `footprint`, run the workload (open and archive 20 tasks, switch
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

- **The click waited for everything before showing anything.** New Task made the worktree,
  waited for the agent and asked for the session before the task existed anywhere on screen, and
  ignored any other New Task meanwhile ("one at a time"). Now the click adds a starting task to
  the sidebar and selects it at once (`AppModel+StartingTasks.swift`): its composer takes the first
  message, which goes out when the session exists, and the worktree and the agent start at the same
  time. A failure stays on the task with Retry and Discard instead of an alert.
- **Git checked a new worktree out one file at a time.** This change used a checkout
  worker per core, which halved it on this repository. The CPU cost led to the bounded checkout
  policy below. Sparse and
  `--no-checkout` worktrees were ruled out: the agent has to see the whole project from its first
  turn. Cloning the main checkout's files (APFS clones) was measured too and lost: populating took
  9 s and refreshing the index another 18 s.
- **Nothing scans the repository on the main thread.** The worktree, the env-file copy
  (`git ls-files --ignored`, 0.35 s here), the status scan of the new worktree (0.4-0.8 s) and the
  file list for `@` mentions (only when one is typed) all run in git's own processes or off the
  main actor; `sample` shows the main thread idle throughout.

### Worktree creation CPU

2026-10-23, a 16-core Mac, Git 2.56.0, Debug. Before: `bb908dba`, which passed
`checkout.workers=0` to every worktree creation. After: one checkout worker and `nice -n 10`,
applied through the host's command runner to new, detached, existing-branch and restored worktrees.
The command overrides all-core user settings without changing the repository's saved config.

Three runs per fixture through `Repository.addWorktree` followed by `copyIgnoredFiles`:
a local Native clone with 6,277 tracked files, and a generated JavaScript monorepo with 100 packages,
30,102 tracked files and 60,000 ignored files under `node_modules`. LFS smudging was skipped;
no setup scripts or downloads ran. `ps` sampled the Git process tree at a 50 ms target interval;
100% means one logical CPU. `/usr/bin/time -l` measured cumulative child CPU. These are medians
on a shared Mac, not a hard CPU cap or a latency guarantee.

| Measurement | Native before / after | JavaScript before / after |
| --- | --- | --- |
| Peak sampled Git CPU | 380% / 79% | 650% / 99% |
| Git processes at peak concurrency | 18 / 2 | 18 / 2 |
| User + system CPU time | 2.87 s / 0.65 s | 10.67 s / 1.80 s |
| Checkout wall time | 0.64 s / 0.65 s | 1.81 s / 1.81 s |
| Checkout process nice value | 0 / 10 | 0 / 10 |

Ignored dependency trees stayed out of the checkout; the JavaScript fixture's `.env` was copied.
The two remaining Git processes are `worktree add` and its checkout child, with no per-core worker
fan-out. Larger repositories can take longer with one worker; the already-visible starting task
and editable composer cover that wait.

The isolated app's `New Task in native` and `New Task in js-monorepo` actions also reproduced the
16-worker fan-out before the fix. One app run each before and after measured peak Git CPU of
208% / 64% for Native and 598% / 94% for JavaScript. The fixed checkout ran at nice 10 with no
per-core workers. Both tasks reached their composer with clean, complete worktrees; `.env` was
copied and `node_modules` was absent. A separate app CPU load existed before the click and in a
branch-only control with no worktree: sampling showed menu updates and initial history indexing.
That independent load is not included in the Git numbers above.

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
  The floor must cover the whole column, including notices above its page. The detail page's
  floor left "While you were away" outside it, so a recovery headline measured a character per
  line and forced the window past the screen. On 2026-10-21, a seeded host recovery followed by
  a finished task reproduced this in both checked launches: a 1,000 x 620 window became
  1,000 x 1,620, with `-nativeWindowFrame` and with a normally restored frame. `RootDetailColumn`
  now applies the floor to the notices and page together, preserving the headline's full text.
  Ten consecutive launches with that same notice stayed at 1,000 x 620 (five placed, five restored).
  Resizing to the minimum and back, and dismissing the notice, also kept the chosen size.
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
  (`Section` inside it), so only the rows on screen are built and measured. Most of what was
  left was the inspector column sliding open, which the second pass below takes out.
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

A second pass, the same evening and method, took the three things the first left (on a fresh copy
of the 250-change repository; the clean one has a single committed file):

| Measurement | Before | After |
| --- | --- | --- |
| Opening the inspector on a clean repository | 280–383 ms | 69–77 ms (174 ms the first time) |
| Opening it on 250 files | 150–550 ms | 218–392 ms |
| Selecting a small file | 184–220 ms | 105–196 ms; of a profiled one, over half was the Accessibility press driving it and the accessibility tree it updates, leaving about 40 ms |
| An agent writing 3 files every 100 ms for 10 s: main-thread time | 147 ms | 44 ms |

- **The column slid open, laying the window out every frame.** The inspector's split view item
  animated in: a layout of the whole window before and after, and another on each frame of the
  slide, for about two thirds of opening on a clean repository. Inspectors now appear and go
  without sliding (`SessionView.openInspector`, a transaction without animations), in one layout.
- **The session view re-rendered on every rescan.** It read `status` for its subtitle and the
  Commit action on the files-changed card, so each rescan re-ran its body, transcript included.
  `GitRepositoryModel` now mirrors what it shows, `summary` and `canCommit`, writing each only when
  it changes, as `SessionModel` does for its state.
- **Selecting a file drew the pane three times.** A loader replaced the previous diff, the new diff
  drew plain, then again once highlighted. The pane now shows the model's `shownDiff`, which moves
  to the new file once its diff is ready, so a quick load replaces the previous diff in one draw
  (a slow one shows the loader after 150 ms), and diffs under the Load Diff limit come back
  highlighted (`DiffLayout(path:oldText:newText:)`), so the first draw is in color.

### Long transcripts

2026-10-19, Debug build in an isolated instance on this Mac's 120 Hz built-in display (M4 Max), with
a dozen agents building alongside (load average 5 to 130, so each figure is a range over runs). A
fake agent (`scripts/perf/long-session-agent.py`) replays a 500-turn session the way Codex's history
looks: about 6,400 items in 9,439 updates (10.8 MB), with prompts, reasoning, commentary, reads,
searches, commands with output, edits with diffs, and Markdown replies with headings, lists, code
blocks and tables. Folded, the transcript is about 290,000 points tall. `scripts/perf/scroll.swift`
scrolls it from the bottom up and back for 12 s; frames come from `-framePacing YES`, the main
thread's profile from `sample`. The view fixes were tried one at a time in a copy of the tree, in one
build switched by a launch argument, then made in the transcript. The original build couldn't open
the 500-turn session in reasonable time, so "before" for scrolling and streaming is the transcript's
views as they were with the model fixes below already in (scrolling runs none of the model's code).

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
  tree under the cursor on every frame the content moved (12–19% of a fast scroll). Turning hit
  testing off while a scroll is under way was tried and taken back out: nobody could check that a
  mouse wheel's scroll always ends its phase, and if one doesn't, clicks in the transcript stop
  working. It's in "Still to do".
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

#### 2026-10-20: measured again, without an accessibility client

On a quieter Mac (load average 7 to 40, a few agents), with sessions in the background host, the
instance's window moved where nothing covers it (`-nativeWindowFrame`), and no accessibility
client. Debug and Release (`NATIVE_PERF`).

- **The scroll numbers above don't hold.** Neither driver used for them moves the transcript the
  way a trackpad does: setting its scroll bar through Accessibility (`scroll.swift`) leaves the
  rows from before on screen, and moving its clip view or sending it wheel events
  (`-nativeAutoScroll`) slides the rows off the end, either way, and draws nothing new. Its scroll
  view is bottom-anchored with a bound `ScrollPosition`, and SwiftUI keeps the rows where it thinks
  they are. A first pass this morning also measured a window other instances covered, which
  isn't drawn at all: 99% of frames "drawn" at 12% of the main thread. The transcript is now
  driven through SwiftUI itself (`-nativeTranscriptAutoScroll`), a prompt or reply at a time,
  each step a screenful of new rows; that's harsher than reading speed, and the numbers below are
  for it. Whether a real trackpad shows the transcript blank when scrolled fast is for a person to
  check.
- **Reopening a session replayed it on screen.** While history replayed, the transcript heard about
  it every 100 ms, and "Loading session…" was an overlay with no background, so the transcript
  showed through it growing and chasing its end: in screenshots every 100 ms of a 500-turn reopen,
  9 frames in a row with 12–31% of the transcript changing. Now `SessionModel.isRestoringHistory`
  (host: replaying, the mirror loading, or the host loading; in-app: until `session/load` answers)
  keeps the loading state in place of the scroll view, and nobody hears about the history until
  it's all in. The transcript then appears once, already at its end, with no animation: one change
  between frames, then only code colors arriving 100–200 ms later (5% of the pixels, nothing
  moves). The same for the 500-turn session in the app and in the host, in light and dark, and
  for a real Codex session after an app relaunch and after a host restart.
- **Lists lay out without a Grid.** A Grid measured every item again to line up the marker column;
  a stack of rows with a hidden copy of the widest marker does the same. GridLayout was 5.7% of the
  main thread with the SwiftUI driver at 30 steps a second (Release) and no longer shows.
- **Tried and taken back:** code that fits its block shown without a scroll view
  (`ViewThatFits`). Sizing the scroll views went from 5.7% to 2.9%, but laying out the code's
  text twice took more than that back.

| Measurement (500 turns) | Release | Debug |
| --- | --- | --- |
| The SwiftUI driver, 10 steps a second, 100 replies up and back | 74% of refreshes drawn, 32 dropped a second, worst stall 245 ms, 6.9 s CPU over 20 s | 76% drawn, 29 dropped a second, worst 91 ms, 5.6 s |
| The same at 30 steps a second | 56% drawn (load 32) | 77% drawn, worst 76 ms |
| Where the main thread goes at 30 steps a second (Release, 45% busy) | laying out selectable text (TextKit 2) 16–19%, the lazy stack placing rows 20% (of which finding each step's row, the driver's own cost, 13%), scroll views in code blocks 3–6% | |
| Streaming a long reply into it | 48% CPU, 70% of refreshes drawn, worst stall 115 ms | 62% CPU, 63% drawn |
| Streaming into a 20-turn session | 38% CPU, 78% drawn | 54% CPU, 81% drawn |

Streaming in a long session costs about a quarter more than in a short one: on every chunk SwiftUI
reads the id of each of the transcript's thousands of lines (`ForEachState.update`, about 13% of
the main thread, and as much again walking them) and `plan()` puts the cached lines together
(11%). The rest, in both, is laying out the growing section's text on every chunk (20%).

#### 2026-10-20, evening: streaming into a long session costs what a short one does

Optimized Debug builds (the recipe in "Measuring": the Debug configuration, so an isolated host, with
Release's compiler settings), the fake agent run from a frozen copy of its corpus (other agents edit
the files it quotes), one project, agent history search off (`search.includesAgentHistory NO`: its
backfill reads every agent's history on other threads), no accessibility client. Before is the tree
at 18:56; after is the same tree with only the transcript changes below. Runs alternated before and
after, and only runs whose window stayed 620 points tall with nothing in front of it count (some
grew: "While you were away" measured at no width, fixed since, see Streaming). The Mac was very
busy (load average 90 to 130), so CPU varies from run to run; instructions a second hardly depend
on the load. Each figure is 15 s of streaming the same long reply, the main thread's share from a 10 s `sample` right after.

| Measurement | Before | After |
| --- | --- | --- |
| Streaming into the 500-turn session | 32.8–32.9% CPU, 1,950–2,010 M instructions/s, 84–88% of refreshes drawn, worst stall 34–36 ms; main thread 45% busy | 28.4–29.2% CPU, 1,350–1,420 M instructions/s, 91% drawn, worst 33–40 ms; main thread 35% busy |
| Streaming into a 20-turn session | 29.4% CPU, 1,440 M instructions/s, 91% drawn | 29.0% CPU, 1,350 M instructions/s, 91% drawn; main thread 31% busy |
| `ForEachState` in the 500-turn session (main thread) | 14.3% (reading every line's id and editing the list on each chunk, then walking it) | 4.1% (20 turns: 3.9%) |
| `plan()` in the 500-turn session | 5.6% | 3.3% |

- **Earlier turns are a list of their own.** The standard transcript plans its lines as two lists:
  every turn before the latest, and the latest (`StandardTranscriptPlan`). The earlier list is kept,
  with its version, until one of those turns changes, and is drawn by `StandardTranscriptLines`, a
  view that's equal to the last one while its version (and the permission shortcut's target and the
  highlighted line) stay the same, so SwiftUI doesn't update it and never looks at its thousands of
  lines while a reply streams. SwiftUI compares it with its own `==` because it's Equatable and not
  plain data; `.equatable()` would have been wrong here: `EquatableView` is a single view, so the
  lazy stack would have built every earlier line at once. In a 500-turn session its body ran twice
  over a whole streamed reply (opening, and the prompt starting a turn), not once per chunk.
- **Rows don't read the session's state.** A row that read `session.state` would have updated on
  every chunk anyway. A thought's clock and a footer's subagents now come with the line, the
  permission shortcuts' target from the session's mirror (`permissionRequests`), and the transcript's
  empty state from `isTranscriptEmpty`; `TranscriptView` no longer reads `state` at all once it shows.
  Session messages still name subagents from `state`, so each one on screen updates with a chunk.
- **Checked against the regressions such a split can bring:** reopened, the 500-turn transcript
  opens at its end and its content measures 362,000 points as rows lay out (as before, not one
  view's height); a search reveal of an item 2,000 from the end finds its line in the earlier
  turns' list and scrolls there; and Native's footprint after reopening is 172 MB (208 MB before).
- **Code colors before a reopened transcript appears**, behind `-transcriptOpeningColors YES`
  until it's been seen working: the code in the last screen and a half of the transcript is
  highlighted (off the main thread, all at once, for at most 300 ms) while "Loading session…" stays,
  so the rows appear with their colors (`TranscriptOpeningCode`). The transcript appeared in every
  reopen with it on, but no probe could yet tell plain code from colored in the first frame: the
  rows render before the scroll view's `onAppear`, and screenshots weren't possible.

#### 2026-10-21: returning to a session's reading position

The window remembers a transcript line and its anchor, plus expanded rows and turns. It restores
that line without animation before showing the transcript, with bounded retries while the lazy
stack lays out. Search reveals take precedence, and leaving during restoration cancels it without
replacing the previous position. A session left at the latest output still opens at the latest;
even a small scroll above it is remembered, with only a half-point rounding tolerance.
The reading snapshot is captured during layout, before child rows discard their frames on removal.
Missing row geometry keeps the previous snapshot; only a measured end records the latest output.
Only this small state survives a switch: no hidden session view graphs, observation or layout.
Entries hold sessions weakly and discard dead entries when another session is first visited.

Checked in isolated Debug with the 20-, 100- and 500-turn fixtures: returning to an earlier line,
expanded tool output, rapid switches, search reveals, Settings, archive/undo and a new task.
The saved row returned within one point in light and dark. After the stress run, footprint was
256 MB with all 620 turns loaded, and idle CPU time advanced 0.01 s over 10 s. This is not an
uncovered-window animation benchmark: other windows partly covered the instance, so screenshots
were checked against row geometry as well.

### Pull request diffs

2026-10-20, Files Changed on vercel/next.js#100215 (124 files) opened with `-gitHubOpenPullRequest
<url>/files`, scrolled by `-nativeAutoScroll` 20,000 points down and back, the window uncovered and
no accessibility client.

| Measurement | Before | After |
| --- | --- | --- |
| 2,000 points a second, Release | 87–91% of refreshes drawn, 10.5–16 dropped a second, worst stall 35–55 ms, 15.8–16.4 s of main-thread CPU over 20 s | 98.5–98.6% drawn, 1.7–1.8 dropped a second, worst stall 29 ms, 9.9–10.2 s |
| 6,000 points a second, Release | 72% drawn, 34 dropped a second, worst 49 ms | 85% drawn, 18 dropped a second, worst 41 ms |
| 2,000 points a second, Debug | 88–94% drawn (load 15) | about the same: Debug is bound by Native's own unoptimized code |

- **A quarter of the main thread asked ColorSync about colors.** Diff blocks draw in text views,
  and Core Graphics asked for each color's HDR headroom every time it drew a run: 24% of the
  samples, ColorSync tag lookups under `CGColorGetContentHeadroom`. SwiftUI resolves colors in
  extended sRGB, for which that answer is about 200 times slower than for plain sRGB (42 ms against
  0.2 ms per 100,000 reads). `PlatformCodeText` now hands its text views plain sRGB colors.
- **The stall at the start of every scroll** (38–84 ms in earlier notes) didn't reproduce without
  an accessibility client: the first second's worst frame is 8–22 ms.

### Launch

2026-10-19, `just perf --fixture`: an isolated instance in four projects, three with icons of their
own, and 30 tasks; Codex as the default agent. Counts are the main thread's work before the first
frame. "Before" is the tree at 19:15, with the plugin cache and the MCP change already in (neither
shows at this scale); "after" is 20:20. The Mac's load average fell from 130-200 to 5-30 in
between, so compare instructions: CPU time and wall-clock time moved with the load as much as with
the changes.

| Measurement | Before | After |
| --- | --- | --- |
| Main-thread instructions to the first frame, Debug, 30 tasks | 6.5-7.1 G | 4.87-5.09 G |
| The same with no tasks | 4.08-4.18 G | 3.70-3.77 G |
| The same in Release, 30 tasks / no tasks | not measured | 4.54-4.77 G / 3.29-3.33 G |
| Main-thread CPU to the first frame, Debug, 30 tasks | 1.0-1.28 s (load 130-200) | 470-494 ms (load 5-14) |
| Main-thread CPU to the first frame, Release, 30 tasks / no tasks | not measured | 430-459 ms / 319-325 ms (load 6-17) |
| First frame, warm, Release, 30 tasks / no tasks | not measured | 536-570 ms / 424-429 ms |
| `appInit`, Release / Debug | not measured / 47-66 ms | 40-46 ms / 47-66 ms |
| What 30 tasks add over none (the sidebar's rows and Home's recent tasks) | 2.7 G | 1.35 G |
| Making the built-in plugins (`BuiltInPlugins.all`) | 243 M instructions, 60 ms | 73 M, 9 ms (54 M, 8 ms in Release) |
| Reading the agents' MCP configuration | 14-21 ms of main-thread CPU | 0.3 ms (it reads off the main thread) |
| From the window's first body to Home's (where Geist's fonts are first made) | 262-267 M | 176 M |
| Idle and hidden, the idle loop ticking every 2 s (`-agentIdleTimeout 10`) | 1.5-2.6 M instructions/s, 0.05-0.08% CPU | 0.27-0.49 M/s, 0.02-0.03% |

- **Launch is AppKit and SwiftUI building the window.** In a Release profile, about 85% of the main
  thread's samples before the first frame have no Native code under them: restoring and laying out
  the window (about 40%), building the main menu from 80 command items (8%), creating the window and
  its toolbar (7%), Core Animation's first commit and drawing text (10%). Native's own code is the
  rest: NSApplication starting up, the built-in plugins, and the rows' bodies. That's why Release
  does only about 6% less work than Debug, and why the budget of 150 ms (about 1.5 G instructions)
  is out of reach of small fixes: the window has to get simpler.
- **The sidebar was the largest part Native controls.** Every task row was built and laid out
  before the first frame, each about 74 M instructions, in a plain `VStack`. The rows are lazy now,
  so only those on screen are built, and one delete confirmation serves the list instead of one per
  row: 30 tasks add 1.35 G instead of 2.7 G. A built row still costs about 45 M, and the sidebar
  with 30 tasks is about 1.9 G of the 4.9 G (it's 3.1-3.6 G with no sidebar at all), the status
  bar about 0.1 G and Home about 0.25 G.
- **Checking the script runtime's signature hashed 41 MB on the main thread.** Making the
  orchestration plugin made its `ScriptRunner`, which checked that the runtime is signed into the
  App Sandbox: a full static signature check of the 41 MB binary, about 50 ms of Debug launch. The
  check now runs before the first script, once; a runtime that fails it is refused then.
- **Geist was looked up by family name.** Each token font searched every font installed (about
  0.4 ms each, for the dozen or so launch makes), after listing every family to see whether Geist
  registered. Fonts
  are now made from the bundled files' own descriptors, and registering them says whether they're
  there; the text draws the same, pixel for pixel.
- **The agents' MCP configuration was read on the main thread before the first frame**
  (`~/.claude.json` is 315 KB here). It's read in the background now; agents that apply MCP
  switches at launch wait for it through `NativePlugin.prepareForLaunch`, alongside the login
  shell, which takes longer anyway.
- **The plugin registry worked its lists out on every read.** `plugins`, `enabledPlugins` and
  `agents` copied every manifest each time, many times per window update and on every idle tick.
  They're now kept until something they come from changes (the loaded plugins, the user's choices,
  experiment values or the organization's policy), which observation reports.
- **Custom layouts placed their subviews twice.** A `Layout` that doesn't implement
  `explicitAlignment` gets one that places every subview to merge their alignment guides, whenever
  a parent asks. Home's card grid and the status bar have no guides to merge, so they answer nil.
- **CPU time isn't steady on a busy Mac either.** The same launch took 0.5 s or 1.2 s of main-thread
  CPU depending on the load, since a busy Mac runs the main thread on efficiency cores. Instruction
  counts stay within a few percent, so `LaunchMetrics` logs them (`thread_selfcounts`, looked up at
  run time) and `just perf` and `rusage` show them.

#### Round two: the background host, and what's left

2026-10-20, `just perf --fixture` on `main` with the background host on by default, Debug and
Release (load average 6 to 25). Instructions are the main thread's before the first frame; the
per-change rows compare the same build with the change switched off, five or six launches each.

| Measurement | Before | After |
| --- | --- | --- |
| Debug, 30 tasks | 3.55-3.59 G, but the first frame had no tasks in the sidebar (below); 5.29-5.64 G once it did, in a 1623×1040 window | 3.73-3.98 G (1120×780), 466-567 ms of main-thread CPU, first frame 616-797 ms |
| Release, 30 tasks | not measured | 3.45-3.68 G, 481-518 ms of main-thread CPU, first frame 669-734 ms, `appInit` 49-68 ms |
| Rows that don't run their bodies again when the list rebuilds | | 0.4 G less by the window's first layout, about 0.6 G less to the first frame |
| Skills, Open In's apps, agent app icons and folder comparisons off the main thread or skipped | 5.29-5.64 G | 5.05-5.42 G |
| The status bar's items a frame after the bar | 3.97-3.98 G | 3.90 G (the bar now costs about nothing in the first frame) |
| What's left, by taking each away | | the sidebar 0.76 G (its rows 0.19 G of it), Home 0.2 G, the menu bar's items 0.19 G, the rest the window itself |

- **The first frame lost the sidebar's tasks.** With the background host on by default, launch
  waited for the host before `model.start()`, which is what made the runtimes the sidebar lists
  tasks by. The first frame showed "Start a session" under every project and the tasks came in
  later; the launch numbers looked better for it. The saved agents' runtimes are now made with the
  model, and they run in the host if it connects before they start (`AgentRuntime.runInHost`);
  nothing starts an agent before the app has decided where agents run.
- **Every list update rebuilt every row.** The project list rebuilds its rows whenever it updates
  (the filter binding and each project's expansion binding count as changed every time), and each
  row's context menu, accessibility actions and tooltip were built again with it. `SessionRow` is
  `Equatable` on what it shows, so a rebuilt row with the same inputs keeps its body; what changes in
  a row reaches it through what it observes.
- **Rows asked the file system about their folders.** The pull request menu and the row's
  indicators compared each task's folder with its project's by resolving both paths, several times
  per row. Identical spellings are now the same folder without a look at the disk.
- **Skills were read on the main thread.** Like the MCP configuration before, the first read of
  every skills folder now runs in the background and agents wait for it (`prepareForLaunch`).
- **Launch Services on the main thread.** Open In's list of apps and the agent icons taken from
  installed apps are looked up in the background.
- **What stays is the window.** Taking each part away in turn: the sidebar costs 0.76 G, of which the
  rows on screen are 0.19 G now; Home 0.2 G; the menu bar's 74 command items 0.19 G. In a profile,
  restoring and laying out the window, building the main menu, creating the window and its toolbar,
  and Core Animation's first commit are about 85% of the main thread before the first frame, and
  Native's own code the rest. Release does about 7% less than Debug.
- **The menu bar can't wait.** Building its items after the first frame took 0.19 G off launch, but
  SwiftUI drops a menu that has no items when the app starts (File, whose items all come from the
  registry) and never puts it back, so the items are built at launch as before.
- **A launch's numbers depend on the window's size.** macOS restores the window as the last launch
  left it, and a bigger window lays out more rows: the same build measured 3.6 G at one size and 4.2
  G at another. `just perf --fixture` now opens the window at its default size every time.

#### Round three: the menu bar, Home's cards and age labels

2026-10-20, evening. Optimized Debug builds (the Debug configuration compiled like Release, which
keeps the development host), launched in the background (`open -g`) into `just perf --fixture`'s
workspace while the Mac was in use, so the window stayed covered by other apps. Before and after
are one snapshot of `main` with only this work's files different, six launches of each, alternated.
In the before build each menu item reads eight focused values of its own; in the after build the
menu bar reads them once and its items keep their bodies while they show the same (the first bullet
says what shipped). The menu rows compare each build with and without the menu bar's items, through
a temporary launch argument; they count main-thread instructions from `willFinishLaunching` to
`didFinishLaunching`, where SwiftUI builds the main menu and the window first lays out.

| Measurement | Before | After |
| --- | --- | --- |
| The menu bar's items at launch (with them minus without, per pair of launches) | 0.23-0.33 G, median 0.29 G | 0.22-0.36 G, median 0.31 G |
| Menu item bodies run at launch | 84 | 84 |
| Menu item bodies run per task switch, the app in the background | 10 | 1 |
| Main thread per task switch (between two fixture tasks) | 671-688 M | 675-692 M |
| Menu item bodies run per shortcut change, which reaches every item | 170 | 1 |
| Main-thread CPU to the first frame, menu items included | 330-423 ms | 354-379 ms (with Home's four cards) |
| Home's first frame | one card, and the grid reflows to four about 350 ms later | the four cards, in their final layout |
| Home's cards in the window's first layout | | 0.06 G more (three more cards) |
| Idle with the window covered, 150 s | 0.94 M instructions/s, 0.03% CPU, 0.4 wakeups/s | 0.53 M/s, 0.04%, 0.5/s |

- **The menu bar's cost isn't reading focus.** Each of its items read eight focused values of its
  own. The after build read the window's context once for the whole menu bar (`NativeMenuBar`), and
  its items kept their bodies while they showed the same, acting on the context the menu bar read
  last. Launch didn't move: the items cost 0.29 G before and 0.31 G after, within the launches'
  spread. Their cost is SwiftUI building about 85 items' view lists and platform items. Item bodies
  per update fell from 10 to 1 per task switch and from 170 to 1 per shortcut change. The
  main-thread instructions per change didn't fall measurably, though, with the app in the
  background. A real focus change needs the window key, which these measurements can't do without
  bringing the app forward, so its cost is unmeasured. What shipped is the simpler half: the menu
  bar reads the context once and passes it down, and the items build and update as they did before
  (10 bodies per task switch, all of them per focus change). It wasn't measured on its own;
  neither half moved launch.
- **Home's cards are there from the first frame.** Agents that the last launch's check found
  installed get runtimes with the model, like agents with saved sessions (`AgentInstallations`
  keeps the set). The first frame shows every card in its final layout, and nothing moves once
  agents are checked. A click before the check opens the new task's starting screen, which waits for
  the agent; one that turns out to be uninstalled fails there with how to add it. A card whose agent
  went away since the last launch fades out while the rest move over.
- **Ages share one minute clock.** `CompactAgeText` and Home's recent tasks each ran a
  `TimelineView(.everyMinute)`, about 17 with the fixture on screen. They now read `DSMinuteClock`,
  which ticks on the minute while the app can be seen and stops while it's hidden, minimized or
  covered, catching up as it shows again. In a harness it ticked at 21:25:00 and 21:26:00 exactly.
  In 20 s windows a minute tick doesn't stand out from the noise in either build (13-31 M
  instructions per window across a minute or within one), so its saving is below what these idle
  samples resolve.
- **Shortcut changes get slower each time.** In both builds the first change of a shortcut cost
  0.3 M main-thread instructions and the twelfth 3.4-4.5 M, about 1.5 times the one before (Still
  to do).

#### Remaining minute labels

2026-10-21. The seven remaining `TimelineView(.everyMinute)` call sites now use `DSMinuteTimeline`:
pull request row ages, the list's updated label and stale banner, the usage account's limit windows,
the context breakdown's subtitle, and the limit chip and banner. The wrapper reads `DSMinuteClock`
in its own body, so minute ticks update only the time-dependent content. The pull request header
and stale banner format strings inside it instead of giving `Text` a relative-date format that
can schedule updates of its own. Limit resets and scheduled resumes still use their existing
model timers; only display updates share the minute clock.

Normal Debug, isolated `menu-perf`, comparing `a20fd415` with this change on the same base. The
pull request list was open in a covered window, with no Accessibility reads during each 65-second
`scripts/perf/rusage.swift` sample. Before: 0.60% CPU, 0.0 idle wakeups/s, 1.2 interrupt wakeups/s,
31.58 M instructions/s. After: 0.56%, 0.0/s, 0.7/s, 25.20 M/s. These single samples on a busy Mac
do not establish a measurable CPU saving; the concrete change is removal of every per-view minute
timeline. The menu and launch measurements above are unchanged.

### Idle, memory and leaks

2026-10-19, evening, Debug build in an isolated instance: 30 tasks from a fake agent in three small
projects with icons and repository scripts, a shallow clone of the Linux kernel as a fourth project
(96,080 files, 20,000 remote branches), GitHub signed in, the status bar shown. Idle numbers are
kernel counters for Native alone over 120 s windows (30 s ones swing with the Mac's own activity),
several runs each. Task switches and Settings visits are AX presses on the instance's pid.

| Measurement | Before | After |
| --- | --- | --- |
| Idle, visible, status bar shown | 0.18–0.33% CPU, 0.6–0.8 wakeups/s (0.04%, 0.4/s with the bar hidden) | 0.02–0.03% CPU, 0.4–0.5 wakeups/s; 0.08–0.14% later in the evening, where `sample` finds Native's own code in two status bar redraws a minute and the rest in the system |
| Idle, minimized / hidden | 0.05–0.08% / 0.01–0.07% CPU, 0.5–0.9 / 0.7–1.5 wakeups/s | 0.03–0.06% / 0.03–0.08% CPU, 0.4–0.5 / 0.4–0.6 wakeups/s |
| Opening tasks one after another | 140 MB → 2.6 GB after 25 tasks, then a core busy for good and still growing (1.15 GB and 4.9% CPU with the bar hidden) | 30 tasks opened: 136 → 174 MB; 30 more switches +27 MB while caches fill, then −3 to +1 MB per 30 |
| 30 task switches + 10 Settings visits (Projects pages, MCP Servers, AI Instructions and others), after a warm-up | (the run above) | +14, +6, +3 MB in three rounds with the bar hidden; +12.5 MB with it shown |
| `leaks` after the workload | 0 at launch; 2,024 (416 KB) after 30 tasks, 16,572 (2.9 MB) after about 150 switches | 0 |
| Footprint with the kernel project | | Home 142 MB (129 without it); a kernel task costs what a small project's does; an `@` mention there +14 MB for the 96,000-file index |
| Left a session after a long Codex reply | 167 MB → 252 MB (+85 MB) | +28 MB after the first reply of a run (mostly once-only costs of the first Codex session), +8 MB after the next, the same as the fake agent's long reply (+7 to +10 MB) |
| An open, unused Claude Code session | | About 650 MB (the `claude` process 186–200 MB, plus this Mac's MCP servers, which it starts per session: 62 + 393 MB) and 0.5% CPU, 16 wakeups/s; the adapter itself 65 MB, shared |

- **Keep Awake multiplied its own observers.** It followed the number of working tasks with a
  `withObservationTracking` re-armed from its `onChange`. Reading that number goes through the
  sidebar's cached session lists, which bump their generation inside the changing property's
  `willSet`, so one change reached Keep Awake twice and it re-armed twice. Observers doubled with
  every change: 327,000 live trackings, 9.5 million key-path sets and 10.5 million closures after
  the warm-up (4.98 GB), and every later property write walked them all. It now follows with
  `Observations`, which reads again once per change, and assigns only a changed value. A 60-line
  standalone program reproduces it; the cache documents that it must be read from SwiftUI or
  `Observations`.
- **The status bar sampled and redrew every 3 s for as long as it showed.** Resources sampled every
  process tree and assigned a new snapshot (a new date each time), so the bar re-rendered, laid
  out and committed every 3 s: the whole visible-idle regression. It samples every 3 s only while a
  task works or the details are open, every 30 s otherwise and at once when the working tasks, the
  agents or the details change; and the bar reads only what it shows, assigned when that changes.
- **The status bar's memory read as Native's own.** It summed Native and every agent's process tree,
  MCP servers included: the 1.6–2.6 GB in screenshots with the kernel project was the agents,
  Native itself was 140–200 MB. The bar now shows Native and Agents as separate figures, memory and
  CPU each, and the tooltip says what each counts.
- **GitHub refreshed every 10 minutes while nobody could see it.** About 0.5 s of CPU in `gh` per
  refresh (four calls), roughly 0.1% averaged, twice the hidden budget, for counts in a hidden
  window. It now sleeps while no window is visible and refreshes on coming back if results are
  older than a minute.
- **The composer's rich text editor leaked on teardown.** SwiftUI's `TextEditor` bound to an
  `AttributedString` leaves a retain cycle (`NSSwiftMutableAttributedString` and its string proxy)
  behind each editor that goes away, about 14 KB per task switch, and nothing else in Native leaks.
  The composer now uses the plain editor until a draft has code in it.
- **The once-a-minute idle tick re-applied plugin experiments.** About 30 ms of main-thread CPU per
  tick in Debug, the hidden budget on its own, in `PluginRegistry.plugins`; the registry now keeps
  its applied list (Launch, above).
- **Whole-window redraws briefly hold about 257 MB of graphics memory.** At every launch, and on some
  redraws when other windows uncover Native's, `footprint` shows about 257 MB of "Owned physical
  footprint (unmapped) (graphics)" for about a second (peak 390–405 MB), then it drops back to
  130–140 MB. No app code runs meanwhile; it doesn't happen while hidden.
- **The first task opened costs about 50 MB, in any project.** That's the session view's SwiftUI
  graph: `malloc_history` finds 26 MB of new live allocations, spread over SwiftUI and
  AttributeGraph state with no app-side owner, and the allocator keeps the pages its transient
  allocations freed. Later tasks cost 0.5–3 MB each. With the kernel project, git status,
  20,000 branches and the worktree list cost nothing measurable until something asks for them.
- **Idle closing is faithful for Claude Code, and pays.** With claude-agent-acp each session is its
  own Claude Code process, which starts the user's MCP servers for itself: two unused sessions held
  1.3 GB and 1% CPU. A closed session's whole process tree exits; selecting it loads it back in
  about 6 s (Debug, busy Mac) with its transcript, model and effort (Opus 5.5 at Low), autonomy
  (Accept edits), Native's mode and title. Only the turn's duration and the context gauge wait for
  the next turn. Claude Code's plugin now closes sessions unused for 10 minutes
  (`idleSessionTimeout` in the agent manifest, docs/plugins.md); the `sessionIdleTimeout` default
  still overrides it for every agent. Codex uses host idle unloading instead (below).
- **Every Codex task ran the user's MCP servers twice.** codex-acp 2.2.2 titles a new session
  itself after its first turn, with a model, on a thread of its own that it never releases
  (codex-acp#628), and Codex starts the user's MCP servers for every thread. With a `~/.codex`
  config of four servers (an `npx` one among them), five new tasks held 53 processes and 5.31 GB
  under the host, about 1 GB a task. Native now names a new session in Codex before its first turn
  (`renameCommand`, codex-acp's `/rename`, which asks no model), so that thread never starts: the
  same five tasks hold 28 processes and 2.79 GB, about 0.5 GB a task, and each saves a model call.
  With host titles on, Native's title replaces the name before the next turn, so `codex resume`
  lists tasks as Native does.


#### Codex idle unloading, 2026-10-21

Five real Codex sessions in the isolated `codex-idle` Debug instance on elara, using codex-acp
2.2.2, `gpt-6.1-sol` and Low effort. Each completed a short coding prompt without using tools,
then sat idle for the shipped 600-second timeout. Other prewarmed adapters were stopped before
the baseline. These are `footprint --noCategories -f bytes` totals for the host and its descendants,
not the app's own memory. Elara's MCP configuration differs from the earlier Mac measurements.

| State | Processes, including host | Physical footprint |
| --- | --- | --- |
| Five completed tasks, still loaded | 19 | 406.5 MiB |
| After idle unloading | 1 | 11.2 MiB |
| One task resumed and answered again | 7 | 200.5 MiB |
| That task closed with `session/close`, sampled 5 s later | 6 | 197.9 MiB |

The host released 395.3 MiB (97%) and every Codex descendant exited. Closing one thread alone
retained its MCP processes; stopping the adapter freed them. Codex's manifest now enables
`idleUnloadTimeout: 600`: the host checks at most every 30 seconds, closes eligible idle sessions,
and stops the adapter once nothing still needs it. Working turns, approvals, questions, hidden
commands, retries and active queues keep their agent alive.

Attaching to read the parked transcript left Codex stopped. Sending a follow-up restarted it and
completed a reply in 5.6 s. The host protocol emitted no history reset or loading phase, and the
conversation and settings remained intact. The regression tests additionally restore a non-default
model and effort and exercise waiting approvals and questions. The live check used production code
at `31c1bd74`, including the child-history fix. Completed direct and nested children also have
failing-before and passing-after host-protocol regression coverage. Elara cannot drive or capture the UI, so the visual check of quiet return remains for the
main Mac.

## Still to do

| What | Why | Owner |
| --- | --- | --- |
| Stop hover hit-testing while the transcript scrolls | 12–19% of a fast scroll, measured with an accessibility client and the cursor over the transcript. Can't be verified by a script: the cost needs the real cursor over the rows, and the proof (clicks and hover come back the moment a scroll ends) needs a real mouse wheel and trackpad, whose scroll phases no synthetic driver reproduces for this scroll view | Transcript performance, by hand |
| Release individual closed Codex threads while another task runs | The host now stops the adapter once every task is idle for 10 minutes. While another task keeps it running, a closed thread's MCP servers still wait for Codex's 30-minute `thread_unload_delay_secs`, which codex-acp cannot pass | Upstream Codex and codex-acp#629 |
| "Couldn't run git: The file “project” doesn't exist" alert | New Task in a project whose folder is gone shows a modal; the sidebar already says "Can't find this project's folder" with Retry | Failures |
| Launch within 150 ms of main-thread CPU | 481-518 ms in Release with 30 tasks (3.45-3.68 G instructions): mostly AppKit and SwiftUI restoring, laying out and drawing the window (Launch, above). It takes fewer views before the first frame, not faster code; the sidebar outside its rows (0.57 G: the navigation items, the project headers, the scroll view and its key handling) is the largest part Native controls | App shell, sidebar |
| A cheaper main menu | 0.29-0.31 G of launch in optimized Debug (Launch, round three): SwiftUI building about 85 items' view lists and platform items. Reading the window's context once instead of eight focused values per item didn't change it. Building the items after the first frame loses the File menu (round two). Fewer items at launch might: submenus whose items come when they open (Selected Tasks, Mode, Status Bar Items, Keep Mac Awake, Appearance), if SwiftUI keeps a submenu that starts empty, or fewer than the nine Go to Task items | Commands |
| Native under 150 MB with a transcript open | 175–195 MB with one short transcript open (Home 130–140 MB): the first session view's SwiftUI graph is about 26 MB live, the rest pages the allocator kept after its transient allocations | Session view, transcript |
| About 257 MB of graphics memory on whole-window redraws | For about a second at every launch and on some redraws when other windows uncover Native's (peak 390–405 MB); find what draws in-process with Metal then | App shell |
| Changing a shortcut gets slower each time | Each change in a session costs about 1.5 times the one before: 0.3 M main-thread instructions for the first and 3.4-4.5 M for the twelfth, with the menu items rebuilt for each change or not (Launch, round three). Something that follows the bindings compounds; find what | Commands |
| The composer's rich editor still leaks once it showed code | SwiftUI's rich `TextEditor` leaves about 14 KB behind each editor that goes away; only drafts with code use it now. Keeping one editor across task switches would end it | Composer |
| Park the default agent when it has no open sessions for a long while, or start it on the first New Task | It's kept running so New Task never waits; with direct adapter launch that wait is now about 0.3 s for Codex. Codex itself is now ended by the host once nothing has used it for 10 minutes (`idleUnloadTimeout`) | App model |
| Opening the changes inspector on many files under 100 ms | Still 218–392 ms on 250 files against 69–77 ms on a clean repository: laying out and drawing the rows on screen (text measuring, the diff's selectable text) and the first file's diff, in Debug | Git |
| Scroll a long transcript at 120 Hz | With the SwiftUI driver a screenful of new rows costs 25–80 ms (Release): their selectable text (TextKit 2) and the lazy stack placing them. Lists no longer use `Grid`; code blocks without a scroll view each didn't pay (`ViewThatFits` laid the text out twice). Not measured again on 2026-10-20 (every part of the screen was covered by other windows). Next to measure: what selection costs (reply sections without `.textSelection`); list markers without selection (each item has two marker texts, a hidden widest copy and the marker, both selectable today); and code that fits shown without a scroll view, decided from its longest line and the code font's advance rather than by laying it out twice. First check by hand whether fast trackpad scrolling shows the transcript blank: no synthetic driver can tell | Transcript |
| Streaming within budget | The 500-turn session now streams at the 20-turn session's cost (Long transcripts, "2026-10-20, evening"), but both keep the main thread 31–35% busy in an optimized build, over the 25% budget: what's left is laying out and drawing the growing section on every chunk (its text 11–12%, committing the frame 14–16%, which includes that layout). Laying out only the section's last paragraph again, or chunks coalesced to the display's rate, are the next things to try | Transcript |
| Code colors arriving after a reopened transcript appears | The code blocks on screen draw plain for 100–200 ms. `-transcriptOpeningColors YES` highlights them before the rows appear (Long transcripts, "2026-10-20, evening"); turn it on by default once a screenshot sequence of a reopen shows no plain code. Also: a streaming reply is split into sections whole on every chunk (1–1.5% of the main thread here, growing with the reply); splitting only its last two sections again is equivalent, since new text can only move the boundary before the last one | Transcript |
