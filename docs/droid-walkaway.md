# Walk-away test

The droid promise (docs/droids.md) end to end: start a task on a droid from the laptop, the laptop
really sleeps, the droid finishes the task during that sleep, and the laptop shows the result once it
wakes. This page is the runbook and the evidence record. `scripts/tests/droid-walkaway.py` is the
droid's side; its offline tests are `scripts/tests/test_droid_walkaway.py`.

**Status: walk-away pending.** The droid's side, the fixture and the stand-ins are done. The real sleep
hasn't been run, and the stand-ins found a failure that the real run would hit (Failures, 1).

## What runs where

| | The laptop (main Mac) | The droid |
| --- | --- | --- |
| Build | isolated Debug instance `droid-walkaway` (`scripts/dev/run-isolated.sh`) | Debug build of the same commit, unsigned, bundle id suffix `.dev.droid-walkaway`, in `~/droid-walkaway/dd` |
| Host | the instance's own development host | the build's host on its own development channel, a launchd job for the login session only (as the app starts a development host) |
| Data | the instance's defaults and Application Support | `~/droid-walkaway` (fixture, task worktrees, evidence) and `~/Library/Application Support/Native/Channels/<channel>` |
| Never touched | the installed Native, its host and data | the installed Native, its host and data, other folders, system settings, credentials |

Switches for the run, all shipping defaults except the first:

- `NativeRemoteHosts YES` on the laptop: the only switch the path needs (docs/durability.md, "Titles").
- New Task's "Runs on" picker (the Compose page, `NativeComposeTask`, stays off).
- Pairing grants from Add Host's defaults: run commands and edit files (`runCommands`) and install
  updates (`manageHost`, which also lets the laptop configure the droid's titles); plugins off.
- Host notifications on (the default; the droid's host advertises `notificationEvents`).
- Keep Mac Awake on the droid's host: Off, its persisted default. The droid itself never sleeps
  (doctor: `unattended.sleep ok`), so nothing holds an assertion.
- The agent: Claude Code on the droid, Haiku at Low effort through the instance's
  `agentDefaults`, the cheapest real session (a test cost setting, not a product switch).

Supported host tools on the droid, from its doctor: Claude Code, Codex, OpenCode and Pi ready;
node, npx, git and gh (signed in) found; Cursor and Copilot not installed.

Not covered: anything that runs in the laptop's app rather than on the droid's host (workflows,
goals, automations, Native's tools in the app) stops while the laptop sleeps. This test proves only a
task's own turn on the droid.

## The fixture

A tiny repository on the droid, `~/droid-walkaway/fixture`, whose origin is a reserved name that never
resolves (`https://walkaway.invalid/native-tests/walkaway-fixture.git`), so nothing is fetched or
pushed. The laptop's project is a checkout with the same origin, which is how Native knows the two
are one project (docs/durability.md, "Projects across devices"). New tasks start from the local
branch and say "Couldn't fetch the latest remote changes", as expected for that origin.

The task runs `./walkaway next` until it prints `WALKAWAY-DONE`. Each call is one step under Claude
Code's two-minute command limit:

1. `--before` steps (2) of `--step-seconds` (60).
2. Then it holds, one 90-second call at a time, until the observer opens the gate: the laptop was
   connected, then gone for 60 seconds straight. So the finish never races the person putting the
   laptop to sleep. It gives up after `--hold-max` (45 minutes from the start) with `gate-timeout`.
3. `--after` steps (3), then it writes `walkaway-result.txt` (a change in Files Changed), runs its
   test and prints `WALKAWAY-DONE result=pass steps=5`.

Each step appends a mark to `~/droid-walkaway/evidence/marks.ndjson`. Approval is arranged once,
before any sleep: the first `./walkaway next` asks, and "Yes, and don't ask again" saves
`Bash(./walkaway next *)` in the fixture's own `.claude/settings.local.json`, which every later task
there uses. `./walkaway probe` isn't covered, so it still asks (the approval case).

## The helper

`python3 droid-walkaway.py <command>` on the droid, from `~/droid-walkaway` (copied from
`scripts/tests/`). Defaults: `--root ~/droid-walkaway`, `--app ~/droid-walkaway/dd/Build/Products/Debug/Native.app`.

| Command | What it does |
| --- | --- |
| `fixture [--force]` | makes (or rewrites and commits) the fixture repository |
| `host start\|stop\|restart\|status` | the job's host: a launchd job with the build's own plist and label |
| `setup` | as a local client, before pairing: task worktrees into `~/droid-walkaway/worktrees`, the fixture as a host project |
| `pair --json` | `Native Host pair --run-commands --install-updates` for this build's channel; the `invite` line's `link` goes into Add Host |
| `observe --arm` | records the timeline (below) every 5 s, for at most 4 hours, and opens the fixture's gate |
| `gateway off\|on` | stand-in only: the host stops and starts taking paired devices |
| `operator` | turns the laptop's sleep record and clock samples into the operator file; touches no machine |
| `verify` | checks a timeline against the operator file; prints the evidence table; exits 0 only when every assertion passes |
| `clock` | this machine's time, for clock samples |

It refuses (exit 3) an installed Native, a bundle id without `.dev.droid-walkaway`, a plist without a
development channel, a label that isn't the build's own, and a job folder outside the home folder or
inside `~/Applications`, `~/Library` or `~/.native`. It never sleeps or wakes a machine, never
connects to another machine, never reads credentials, and talks only to its own host's sockets.

The timeline (`~/droid-walkaway/evidence/timeline.ndjson`, the droid's clock) records the host's
identity (label, channel, build, system, keep-awake policy, each doctor check's status), the paired
laptop's connection, each task's phase, queue, approval and title source, activity and notification
kinds with their times, the fixture's marks and the gate. No titles, folders, prompts, device names
or addresses: ids are shortened hashes.

`verify` asserts, with times moved onto the droid's clock and every bound narrowed by the clock
uncertainty plus a second:

- the timeline comes from a development host;
- the operator file has a sleep that ends after it starts, and a measured clock offset;
- it's a real sleep: the laptop's heartbeat or kernel record, never a stand-in;
- the fixture worked before the sleep and during it;
- it finished strictly after the sleep began and before the wake, with `result=pass`;
- the fixture's own session's turn ended during the sleep too (sessions are matched to fixture runs
  by a hash of their folder);
- the laptop was disconnected at the finish, and from then on came back only after the wake.
  Maintenance wakes before the finish are allowed.

## Runbook

`d` stands for `scripts/dev/drive.sh droid-walkaway` (in zsh, define `d() { scripts/dev/drive.sh
droid-walkaway "$@"; }`), and `droid` for the droid's SSH destination. The droid's login shell may not
be bash: send scripts with `ssh droid bash -s <<'EOF' … EOF`. Commands on the laptop run from the
worktree root.

### Once: build, fixture, pairing

On the droid, a clone at the commit under test, built as `run-isolated.sh --build` builds, unsigned:

```sh
git clone https://github.com/binbandit/native.git ~/droid-walkaway/native
git -C ~/droid-walkaway/native checkout --detach <commit>
cd ~/droid-walkaway/native && nice -n 10 scripts/dev/build-slot.sh -project native.xcodeproj -scheme native \
  -configuration Debug -skipPackageUpdates -derivedDataPath ~/droid-walkaway/dd \
  NATIVE_BUNDLE_IDENTIFIER_SUFFIX=.dev.droid-walkaway CODE_SIGNING_ALLOWED=NO CODE_SIGN_IDENTITY="" build
cp scripts/tests/droid-walkaway.py ~/droid-walkaway/ && cd ~/droid-walkaway
python3 droid-walkaway.py fixture && python3 droid-walkaway.py host start && python3 droid-walkaway.py setup
```

On the laptop, the same commit, a checkout with the fixture's origin, and the instance:

```sh
scripts/dev/run-isolated.sh droid-walkaway --build
f=/private/tmp/native-playtest/droid-walkaway/walkaway-fixture
mkdir -p $f && git -C $f init -q -b main && echo "# walkaway-fixture" > $f/README.md && git -C $f add -A
git -C $f -c user.name=Walkaway -c user.email=walkaway@example.invalid commit -qm "Walk-away fixture"
git -C $f remote add origin https://walkaway.invalid/native-tests/walkaway-fixture.git
scripts/dev/drive.sh droid-walkaway seed $f
scripts/dev/run-isolated.sh droid-walkaway --no-build -- -NativeRemoteHosts YES -defaultAgent claude-code \
  -agentDefaults.claude-code.model haiku -agentDefaults.claude-code.effort low
```

Pair: start `python3 droid-walkaway.py pair --json` on the droid (it waits up to five minutes), then
`d key cmd+,`, `d press Hosts`, `d press "Add Host…"`, put the `invite` line's `link` in with
`d set "SSH destination or pairing link" -` (from stdin, so it stays out of logs), `d press Continue`,
`d press Pair`. The link is single use; never keep it.

### Before the sleep (the operator, on the laptop)

1. On the droid: `python3 droid-walkaway.py host status`; `host start` if its pid is `none`. Then a
   fresh, armed observer:
   `nohup python3 droid-walkaway.py observe --arm > evidence/observer.log 2>&1 < /dev/null & echo $! > evidence/observer.pid`
2. Launch the instance (the command above, `--no-build`), and check `/tmp/native-tools/screenlocked`
   says `unlocked` before any screenshot.
3. Start the laptop's heartbeat, which stops by itself after three hours, and take clock samples:

   ```sh
   mkdir -p /tmp/dw
   ( end=$(( $(date +%s) + 10800 )); while [ "$(date +%s)" -lt "$end" ]; do date +%s >> /tmp/dw/heartbeat; sleep 5; done ) >/dev/null 2>&1 &
   echo $! > /tmp/dw/heartbeat.pid
   for i in 1 2 3 4 5; do a=$(python3 -c 'import time; print(time.time())')
     r=$(ssh droid 'python3 ~/droid-walkaway/droid-walkaway.py clock' 2>/dev/null | tail -1)
     b=$(python3 -c 'import time; print(time.time())'); echo "$a,$r,$b"; done >> /tmp/dw/clock
   ```

4. A task on the droid: `d press "New Task in walkaway-fixture"`; `d find "Run on"` should read
   the droid's name (`d press "Run on"` and pick it otherwise). Then
   `d set Message "Run ./walkaway next in this folder, one command at a time. Each time it says to run it again, do, until it prints WALKAWAY-DONE. Then reply with only that last line. Don't edit any files yourself."`
   and `d key return`. If it asks, `d press "Yes, and don't ask again for ./walkaway next * commands"`.
5. Wait for the first `"event": "hold"` mark in the droid's `evidence/timeline.ndjson` (about two
   minutes). Then ask the person at the laptop to sleep it.

### The sleep (the person at the laptop)

Put the laptop to sleep (Apple menu ▸ Sleep, or close the lid) within 30 minutes of being asked, and
leave it asleep for at least 15 minutes. Nothing else: don't quit Native or its test window first,
don't touch the droid. Wake and unlock it afterwards, and say so. Only that person ever sleeps or
wakes the laptop; no agent sends a sleep command.

### After the wake (the operator, on the laptop)

```sh
kill "$(cat /tmp/dw/heartbeat.pid)"
s=$(sysctl -n kern.sleeptime | awk -F'[ ,]+' '{printf "%d.%06d", $4, $7}')
w=$(sysctl -n kern.waketime | awk -F'[ ,]+' '{printf "%d.%06d", $4, $7}')
# Five more clock samples into /tmp/dw/clock, as before. Then:
clocks=(); while read -r sample; do clocks+=(--clock "$sample"); done < /tmp/dw/clock
python3 scripts/tests/droid-walkaway.py operator "${clocks[@]}" --heartbeat /tmp/dw/heartbeat \
  --kern-sleep "$s" --kern-wake "$w" --build "$(git rev-parse --short HEAD)" --output /tmp/dw/operator.json
scp droid:droid-walkaway/evidence/timeline.ndjson /tmp/dw/timeline.ndjson
python3 scripts/tests/droid-walkaway.py verify --timeline /tmp/dw/timeline.ndjson --operator /tmp/dw/operator.json
```

Then on the laptop's instance, the same task:

- `d text`: the transcript ends with `WALKAWAY-DONE result=pass steps=5`, with no `Working…` after
  it; `d tree --depth 12 | grep '"Working tasks"'` reads `None`.
- The title is the droid's (`title` is `generated` in the timeline's last session record), or the
  first message shortened (`fallback`) when nothing on the droid can title.
- `d press "Show Changes"`, then `d find walkaway-result.txt`: Files Changed comes from the droid's git.
- Exactly once: `d logs --last 1h | grep HostNotifications` has one `Caught up with <droid's host
  id>: 1 missed` after the wake, then exactly one `Showing turnFinished` (finished within the last
  minute) or `Summing up 1 notifications` (one "While you were away from …" notification) for it.
  The card above the detail column is for a launch, not a reconnection.
- The droid's own proof: `cat ~/droid-walkaway/worktrees/fixture/<task>/walkaway-result.txt`
  (`steps=5`, `result=pass`), the newest folder there.

Screenshots of the task and Files Changed go in the PR with the `verify` table.

### Cleanup

On the droid: `kill "$(cat evidence/observer.pid)"`, `python3 droid-walkaway.py host stop`. When the
test is over for good, also remove `~/droid-walkaway` and the host's channel folder
(`host status` prints it). On the laptop: `scripts/dev/run-isolated.sh droid-walkaway --remove`,
`scripts/dev/drive.sh droid-walkaway seed --remove`, `rm -rf /tmp/dw`.

## Evidence

### Stand-ins, 2026-10-25, main at 94578452

Each one rehearses the run; none is the acceptance run (`verify`'s "real sleep" fails for them by design).
They were checked with `verify` before it matched turns to the fixture's session; their timelines
predate that record, and each run's id matches its task's folder.

| Case | Result |
| --- | --- |
| New Task picks the droid | `Run on` = the droid, its checkout found by repository; the task's worktree made in the droid's worktrees folder |
| App quit (⌘Q) mid-turn, relaunched after the finish | all droid-side assertions pass: disconnect seen at the quit, gate 62 s later, finished 128 s into the 150 s away, turn ended 1 s later, reconnected 4 s after the relaunch. After the relaunch: the "While you were away" card with 1 task finished, the transcript complete, the generated title, Files Changed with `walkaway-result.txt`; one `Summing up 1 notifications` |
| The droid's gateway off while the app kept running, on again after the finish | all droid-side assertions pass (finished 126 s into the 178 s away, reconnected 9 s after). One `Showing turnFinished`. **The task stayed `Working…`** (Failures, 1) |
| Approval round trip | the first `./walkaway next` and a later `./walkaway probe` asked; Yes on the laptop resolved the droid's permission notification and the command ran |
| Queued follow-up | queued with ⌘Return while a turn ran (the droid's session showed 1 queued), sent when it ended, and answered |
| Stop | Stop Agent ended the turn in 3 s; the droid's step process was gone; the transcript says Native couldn't verify Stop for this agent (documented for agents that don't report command lifetimes) |
| Restart of only the job's host mid-turn | the turn resumed ("Native's background host stopped unexpectedly … asked it to pick up where it left off"), finished with `result=pass`, and the laptop showed it finished |

Clock offset between the two machines: +0.12 s, give or take 0.22 s.

The laptop also slept for real for a while during the stand-ins, with no task running. The droid saw
it leave, then reconnect twice for about 30 seconds each while it was asleep: maintenance wakes
reconnect paired hosts. The gate's 60-second rule and `verify`'s "away at the finish" and "back only
after the wake" are there for that.

### Failures

1. **A task that finishes while the connection is down stays `Working…` after it comes back.**
   Repeated twice. Pair a droid, start a task there, turn the droid's gateway off
   (`python3 droid-walkaway.py gateway off`), let the turn end, turn it on again. The transcript gets
   the final reply, the notification says it finished, and the droid's session is idle with
   `end_turn`, but the task shows `Working…` with Stop, and the status bar counts it as working, until
   something else changes that session on the droid. Likely cause: after a reconnect,
   `NativeHostClient.connectOnce` re-attaches each followed session and drops the `AttachResult`,
   whose summary would carry the new phase; the `session/changed` that said idle went out while
   disconnected, and the replayed `turnEnded` event doesn't set the phase (`SessionModel+Host.swift`).
   The walk-away run reconnects the same way after a wake, so it would fail its first after-wake check.
2. **A task on an unreachable droid gives no sign of it.** With the gateway off, the task kept
   "Thinking…" and the status bar said 1 working; only Settings ▸ Hosts said the droid wasn't
   reachable. docs/durability.md says the session header shows the device's state while it isn't online.
3. **Settings ▸ Hosts says "Last connected 10m ago"** four minutes after the connection dropped: it
   counts from when the connection was made, not when it was lost.
4. **The "While you were away" card says "since 6:17 PM"** for a laptop that left at 6:15: it names
   the first missed event's time, which reads as when the person left.

### Acceptance run

Pending: the real sleep, `verify`'s table, the after-wake checks and their screenshots.
