# Performance

Native runs all day next to the user's editor and terminal, so it has to be slim: launch feels
instant, an idle app costs nothing (no CPU, no wakeups, no battery), and memory stays flat however
long it runs. This document is the budget, how to measure against it, and what the measurements
showed. `just perf` reruns the key numbers.

## Budgets

Measured with `just perf` in a Debug build unless it says otherwise. On a busy Mac (a dozen
agents compiling) wall-clock launch times swing by hundreds of milliseconds, so launch also has a
CPU budget, which doesn't.

| What | Budget |
| --- | --- |
| Launch, warm, to the first frame | under 350 ms on an idle Mac (half a Dock bounce), and under 150 ms of main-thread CPU |
| Launch, to `appInit` | under 60 ms |
| An agent ready to take a session | under 1 s after it's needed (the adapter's own start, plus Native's login-shell read once) |
| Idle, window visible, nothing working | about 0% CPU (under 0.1%), under 1 wakeup per second |
| Idle, minimized or hidden | under 0.05% CPU, under 0.5 wakeups per second; nothing animates, nothing polls |
| Memory, typical workspace (a few tasks, one long transcript open) | Native itself under 150 MB footprint; one adapter process per running agent (no npm wrapper) |
| Sessions nobody uses | released, here and in the agent, once that's possible without losing anything (see "Still to do") |
| Streaming a long reply | main thread under 25% busy; footprint back within 20 MB of where it started once the session is left |
| Growth and leaks | under 10 MB after 30 task switches and 10 Settings toggles; `leaks` finds 0 |

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
| `xctrace record --template 'Time Profiler' --attach <pid> --time-limit 30s` | Time profile | Also `Allocations`, `Leaks`, `Animation Hitches`. Open the `.trace` in Instruments |

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
| "+" to visible feedback in the sidebar | none until the session existed (18.2 s); the empty project read "Add an agent to start a session" meanwhile | AFTER_ROW |
| "+" to a usable composer | 18.2 s | AFTER_COMPOSER |
| "+" to the session open (agent ready for the first message) | 18.2 s | AFTER_SESSION |
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
