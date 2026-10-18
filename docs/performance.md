# Performance

Native runs all day next to the user's editor and terminal, so it has to be slim: launch feels
instant, an idle app costs nothing (no CPU, no wakeups, no battery), and memory stays flat however
long it runs. This document is the budget, how to measure against it, and what the measurements
showed. `just perf` reruns the key numbers.

## Budgets

<!-- budgets -->

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

<!-- results -->
