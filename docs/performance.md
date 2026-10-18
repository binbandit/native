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
| Sessions nobody uses | closed after 10 minutes, here and in the agent |
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
compiling), so wall-clock launch numbers are high and noisy; compare the CPU columns.

### Before and after

| Measurement | Before | After |
| --- | --- | --- |
| Launch, warm: `appInit` | 44–66 ms | 58–61 ms |
| Launch, warm: first frame (wall, busy Mac) | 702–1308 ms | <!-- after-frame --> |
| Launch, warm: main-thread CPU to first frame | not measured (added with this work) | <!-- after-cpu --> |
| Launch: agents ready (`agentsReady`) | 2471–4242 ms | 2145–2802 ms |
| Codex adapter start to `initialize` answered | 1085–2185 ms through npx | 287–306 ms direct |
| Claude adapter start to `initialize` answered | 4018 ms through npx | 1332 ms direct |
| Idle, visible, no sessions: Native | 0.07% CPU, 0.6 wakeups/s, 111 MB | 0.05% CPU, 0.9 wakeups/s, 101 MB |
| Idle, hidden: Native | 0.01% CPU, 0.3 wakeups/s | <!-- after-hidden --> |
| Idle, no sessions: processes under Native | 4, 295 MB footprint (npm wrapper 69 MB) | 3, 205 MB |
| Idle, 1 session: Native / everything under it | 0.22% CPU, 0.9 wakeups/s, 94 MB / 14 processes, 990 MB | <!-- after-1 --> |
| Idle, 5 sessions: Native / everything under it | 0.30% CPU, 99 MB / 54 processes, 5.26 GB | <!-- after-5 --> |
| Streaming a 2,500-word reply: Native CPU | 36.7% over 25 s, 88 wakeups/s, 91 mW | <!-- after-stream --> |
| Streaming: main-thread time in Keep Awake | 338 ms per 25 s (a power-source IPC per chunk) | 0 (only when the working count changes) |
| Streaming: footprint | 104 MB → 364 MB (225 MB of it graphics), 138 MB after leaving the session | <!-- after-stream-mem --> |
| 30 task switches + 10 Settings toggles | +6 MB, 0 leaks | <!-- after-growth --> |

### What the measurements showed

- **Every open Codex session holds the user's MCP servers.** Codex starts each configured MCP server
  for every session it has open (here twice: `rea` through npx and the ChatGPT computer-use
  helpers), about 1 GB per session with this Mac's config. Native never closed a session, so five
  tasks opened once held 54 processes and 5.26 GB until the agent stopped, and the default agent
  never stops. Native now closes sessions nobody has used for 10 minutes (`session/close`, which
  codex-acp and claude-agent-acp both support), and drops their transcripts; selecting one loads
  it back.
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
  hidden or covered, as Ghostty's own app does.
- **The Markdown cache could hold a long reply hundreds of times.** It keyed parses by source and
  capped the count at 512, but every streamed chunk is a new source holding the whole reply so
  far. It now also caps the total source size at 4 MB.
- **Launch is mostly the main thread.** Its CPU reaches about a second before the first frame in
  this Debug build. The biggest app-side pieces in the time profile: plugin manifests rescanned
  for experiment placeholders (a regex over every argument) on every `PluginRegistry.plugins`
  read, the MCP config files parsed on the main thread (`~/.claude.json` is 315 KB here), and
  the home card grid's layout. The rest is SwiftUI and AppKit building the window, plus waiting on
  system services (LaunchServices check-in, preferences, window restoration), which a busy Mac
  slows down.
- **Idle with the window visible was already close to zero.** No animation or clock runs when
  nothing works: `TimelineView`s stop with their views, and loaders only show for working tasks.

## Still to do

| What | Why | Owner |
| --- | --- | --- |
| Cache the applied plugin list in `PluginRegistry` (or at least `usesExperiments` per loaded plugin) | `plugins` re-applies experiments, with a regex scan of every manifest, on every read: tens of ms at launch, and again on every redraw that asks for agents | Experiments / plugins |
| Narrow what the composer and sidebar rows observe | While a reply streams, `ModelPill`, `ComposerView`, `SessionRow` and `AppModel.statusBarTasks` re-render on every chunk because they read `session.state`; they need the mirrored `configOptions`, status and title only | Composer, sidebar |
| Render a streaming message in parts | The growing reply is one row; re-rendering it on every chunk is where most streaming CPU and the transient 225 MB of graphics memory go. Split the Markdown at stable block boundaries so finished blocks don't re-render | Transcript |
| Read MCP config files off the main thread at launch | About 14 ms in Debug before the first frame; agents can wait for it instead | MCP |
| Park the default agent when it has no open sessions for a long while, or start it on the first New Session | It's kept running so New Session never waits; with direct adapter launch that wait is now about 0.3 s for Codex | App model |
| Count session listings in flight as in use | So a park never cuts `session/list` short | Failures (agreed, in progress) |
| Night sky on Nightly's home page | Twinkles at 30 fps for as long as Home is shown; a slower rate would look the same | Brand |
