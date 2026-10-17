# Durability

Agents keep working when Native's window closes, when the app quits, and through a crash, an update
or a restart of the Mac. This document is the design: who owns what, how clients talk to it, what is
stored, and exactly what happens after each kind of interruption. The decision is recorded in
`docs/decisions.md` ("Durable by default"); the code is `Packages/NativeHost`, the helper app in
`NativeHostHelper/`, and the app's glue in `native/Host/`.

## The shape

```
 Native.app (client)        iPad / iPhone (client)      another Mac (client)
        │ Unix socket              │ paired, E2E-authenticated        │ ssh … native-host attach
        └────────────┬─────────────┴──────────────┬───────────────────┘
                     ▼   Native Host Protocol (JSON-RPC, NDJSON)
 ┌────────────── Native Host (one per user per machine) ───────────────┐
 │ HostCore: sessions, turns, queues, recovery, activity journal        │
 │ HostStore: SQLite (WAL, synchronous=FULL, fullfsync)                 │
 │ agents ── ACP over stdio ── Claude Code · Codex · Cursor · plugins   │
 │ later: orchestration MCP server, goals/workflows, limit resumes,     │
 │        notifications, keep-awake, menu bar extra, exec + files       │
 └──────────────────────────────────────────────────────────────────────┘
```

- **The host owns everything that has to keep running.** Agent processes, sessions and their turns,
  queued and steered messages, approvals, and (Phase 3) orchestration, goals, workflows, limit
  resumes, notifications and keep-awake. It never shows a window.
- **Every UI is a client.** The Mac app, the iPad app, the iPhone companion and a Mac pointed at a
  Mac mini all speak the same protocol to a host. On the Mac the host happens to be local.
- **Conversations stay with the agents.** A session's history lives in the agent's own store and
  comes back with `session/load`. The host stores only what Native alone knows.
- **A cut-off turn is never replayed blindly.** The host tells the agent it was interrupted and lets
  it check its work (Pi Durable's rule). Native never re-runs a tool call itself.

## Process model and lifecycle

**The helper.** `Native Host.app` is an `LSUIElement` app (no Dock icon, no windows) embedded at
`Native.app/Contents/Library/LoginItems/`. It's an app rather than a bare executable so it can post
notifications with actions and show a menu bar extra under its own bundle id; its display name is
"Native". It links `NativeHost` + `NativeHostMac` and calls `HostMain.start`.

**launchd.** The app registers it with `SMAppService.agent(plistName:)`; the plist sits in
`Contents/Library/LaunchAgents/` and is generated at build time so its label follows the bundle id:

| Key | Value | Why |
| --- | --- | --- |
| `BundleProgram` | `Contents/Library/LoginItems/Native Host.app/Contents/MacOS/Native Host` | runs from inside the app bundle |
| `RunAtLoad` | true | starts at registration and at every login |
| `KeepAlive` | `{SuccessfulExit: false}` | a crash or `kill -9` is restarted; a deliberate stop (exit 0) stays down |
| `ProcessType` | `Interactive` | agents are user-facing work, not background maintenance |
| `AssociatedBundleIdentifiers` | the app's bundle id | System Settings › Login Items shows "Native", not a helper |
| `EnvironmentVariables.NATIVE_HOST_CHANNEL` | empty, or a dev channel | see "Development builds" |

**One host.** launchd runs one job per label, and the host takes an exclusive `flock` on `host.lock`
for its lifetime; a second copy exits 0 (so launchd doesn't restart it). Agents are the host's
children and exit when the host's end of their stdio closes, so they die with the host (checked by
killing the host mid-turn under launchd: no adapters were left behind); Phase 2 also tracks each
agent's process group (npm puts itself in its own) and ends it explicitly, so there are no orphaned
agent trees, ever. (the reference app's
worst bugs were the opposite: daemons from old versions piling up, and an app that read "daemon
unreachable" as "gone" and started a second copy of a running conversation. The lock and the
single launchd label make both impossible.)

**Start.** The app registers the agent on launch (idempotent) and connects. If the user disabled
Native under System Settings › Login Items › Allow in the Background, `status` is
`.requiresApproval`: Native says so, offers to open that pane, and runs an *attached* host instead
(Phase 2): the same binary started by the app, which stops its agents when the app quits. We respect
the user's choice rather than detaching anyway. If the job is registered but not running (it was
stopped on purpose), the app unregisters and registers again, which starts it.

**Quit.**

| Action | What happens |
| --- | --- |
| ⌘Q, closing the window | The app quits. The host and its agents keep working. |
| Native › Quit Native and Stop Agents (Phase 2; its shortcut goes in `docs/keyboard.md` first) | The host cancels running turns (recorded as stopped by the user), stops agents, writes a clean-shutdown mark and exits 0. |
| Menu bar extra › Stop All Agents | Same as above, without opening the app. |
| Logout or shutdown | launchd sends SIGTERM; the host is killed with its agents. Next login it starts and resumes what was running (`systemRestarted`). |

**Updates.** On connect the client compares `protocolVersion` and the host's build with its own.
A newer app asks an older host to restart (`_native/host/shutdown {stopAgents: false}`): the host
takes no new turns, exits with status 75 once nothing is running, and launchd starts the new binary
from the updated bundle. When the user can't wait, "Restart Now" restarts immediately and the new
host resumes the interrupted turns like any other interruption. An older app facing a newer host
shows `incompatible` and offers to update itself.

**Login.** `RunAtLoad` starts the host at login. It resumes only sessions that were working (an
unfinished turn or a non-empty, unpaused queue); idle sessions load lazily when a client opens them,
so login never spawns a dozen agents for nothing.

**Sleep.** While any session is working the host holds a power assertion (`NativeHostMac`, Phase 3,
from the keep-awake engine). Closing the lid still sleeps the Mac unless the user opted into
"keep awake on power"; on wake, agents whose network calls failed surface as failed turns, which the
queue and limit logic already handle.

## Development builds

Several agents build and run Native at once, from different DerivedData folders and checkouts
(Kite quicksaves snapshot one shared working tree, so checkouts differ by build folder, not by
branch). One global host would make them fight: an old binary serving a new app, two apps
registering one launchd label. So each Debug build gets its own **channel**: the plist generator
hashes `BUILT_PRODUCTS_DIR` into `NATIVE_HOST_CHANNEL`, the label becomes `<bundle id>.host.<channel>`,
and the host lives in `~/Library/Application Support/Native/Channels/<channel>/`. The app reads the
channel from its own embedded plist, so app and host always agree. Release builds use no channel and
the standard location. Host state (socket, database, lock) never lives in the repo tree.

Development hosts must not pile up, so they differ from release in three ways:

- **No login items.** A Debug build runs its host as a launchd job for the current login session
  only (`LaunchdSessionJob`: `launchctl bootstrap gui/<uid>` with a plist written to the channel
  folder). launchd still restarts it after a crash, but it never appears under Login Items, never
  triggers "Background Items Added", and is gone after logout. Only release builds use
  `SMAppService`. A Debug build that finds a login item left by an earlier build of itself
  unregisters it, from the owning app as `SMAppService` requires.
- **Idle exit.** A development host stops after 15 minutes with no clients and nothing running.
- **Opt-in per channel.** The host starts only after Window › Durable Sessions › Turn On
  (`NativeHostEnabled.<channel>`). Turn Off stops the host and its agents and unloads the job.

`scripts/dev/clean-host-channels.sh` lists every development host job (labels ending in
`.host.<10 hex digits>`) and channel folder. With `--apply` it stops and disables the ones no running
Native uses (or not named with `--keep <channel>`), and deletes their folders. It never touches a
release host or `~/Library/Application Support/Native` itself.

What Brayden may see while agents develop: a "Native" entry under System Settings › General › Login
Items & Extensions › Allow in the Background, left by a Debug build from before session-only jobs
(two existed on 2026-10-18 and were removed with the script). The script stops and disables those
jobs, so they can't run again; the entry itself goes once that build runs again (it unregisters
its old item) or its DerivedData folder is deleted, or it can be switched off in that list.

## Transport and security

**Local: a Unix domain socket** at `<host dir>/host.sock`. The directory is `0700` and the socket
`0600`. On accept the host checks the peer (`NativeHostMac.CodeSignatureVerifier`): same uid via
`LOCAL_PEERCRED`, then, in signed builds, the peer's code signature via its audit token
(`LOCAL_PEERTOKEN` → `SecCodeCopyGuestWithAttributes`) against "signed by the same team". Ad-hoc
development builds have no team; there the user account is the boundary, as it is for every process
the user runs.

Why a socket and not XPC: the crash tests spawn the real host binary and `SIGKILL` it mid-turn,
which a launchd-registered Mach service doesn't allow; one framing (newline-delimited JSON-RPC,
exactly ACP's stdio framing) carries every transport, including the SSH bridge and WebSocket; and
launchd's `RunAtLoad` + `KeepAlive` already gives what XPC's on-demand launch would. Claude Code's
own background supervisor (`claude --bg`) uses a socket directory the same way.

**Any machine can be a host.** The host core (`NativeHost`) is Foundation-only and portable; macOS
specifics (code signatures, boot time, the login-shell reader, later IOKit keep-awake) live in
`NativeHostMac`, so a Linux build adds a `NativeHostLinux` beside it. Every transport implements
`HostTransport` and yields a `ByteStream`:

| Transport | Reach | Authentication | Status |
| --- | --- | --- | --- |
| `LocalSocketTransport` | this Mac | uid + code signature | built |
| SSH bridge: `ssh <machine> native-host attach` | a Mac mini, a Linux box | the user's own SSH keys; the bridge runs as that user on the remote host | the `attach` side is built; the client's process transport is next |
| Paired network transport | iPad, iPhone, another Mac on any network | QR pairing, then Noise (XX, then IK) with pinned static keys | designed |
| WebSocket + TLS | cloud sandboxes | provider-issued token + pinned key | later |

**Pairing** (shared with the companion, `docs/companion.md`). The Mac shows a QR code carrying the
host's static public key, a one-time pairing secret (valid 5 minutes, single use) and its addresses
(LAN, Bonjour name, Tailscale name). The device connects, runs a Noise handshake that proves the
secret, and both sides pin each other's static keys. Every later connection is mutually
authenticated with those keys, so the network, Wi-Fi or a relay is never trusted. Paired devices are
listed in Settings with a last-seen time and can be revoked; a revoked key is refused at the
handshake. Bonjour finds the host on the LAN; a Tailscale name or a ciphertext-only relay reaches it
elsewhere (open question in the companion doc).

**What a client may do.** Local clients and paired devices are trusted with the full protocol,
including running commands and reading files on the host, because that's what the full UI needs (an
iPad running Git and gh against a Mac). Nothing else gets it: no unauthenticated listener ever opens
on a network interface, the SSH bridge inherits exactly the SSH user's rights, and revoking a device
cuts it off at the next handshake. Approvals given from a device are recorded in the transcript as
coming from that device.

## Host identity and many hosts

Each host has a `HostID` (a UUID kept in its store) and a machine name, returned by `initialize`.
Clients address everything by host: a project belongs to one host (`Project.host`, `.local` today),
and a session is `(HostID, HostSessionID)`. The app keeps one `NativeHostClient` per host it knows;
the sidebar groups projects by host and shows each host's connection state.

**Connection states** (`NativeHostClient.ConnectionState`), each with its own UI:

| State | Meaning | What the user sees |
| --- | --- | --- |
| `connecting` | first attempt | the host's projects dimmed, a quiet loader |
| `connected(HostInfo)` | handshake done | normal |
| `reconnecting(attempt, reason)` | the connection dropped; retrying fast (100 ms, then 0.5–2 s) | "Reconnecting to <host>…"; prompts can still be typed and are sent with their request ids once back |
| `unreachable(reason)` | four failures in a row; retrying every 5 s | "<host> isn't reachable: <reason>", with Retry and, for a remote host, the SSH command that failed |
| `incompatible(hostVersion)` | protocol mismatch | "Update Native on <host>" (remote) or "Restart the host" (local) |

A local host restarting under launchd is back within one launchd throttle interval (10 s), so after
a host crash the app shows `reconnecting` briefly, then the recovered sessions.

**Provisioning a remote host** (Phase 4). From "Add Host…", Native runs over the user's SSH: checks
the OS and architecture, copies the matching `native-host` binary to `~/.native/bin/` (signed and
notarized for macOS; a static build for Linux), installs a user service (a launchd agent on macOS,
`systemd --user` on Linux) so the host survives logout and reboot, and then checks what agents need
there: `node`/`npx` for the ACP adapters, and each agent's CLI (`claude`, `codex`, `cursor-agent`)
on the remote login-shell `PATH`. Missing pieces are listed with the exact install command, never
installed silently. Agents sign in on the remote machine with their own flows (`authenticate` in
ACP), driven from the client.

## The protocol

JSON-RPC 2.0, one message per line. Method names follow ACP where they mean the same thing; Native's
own are `_native/*`. `HostProtocol` in `NativeHostProtocol` defines every method and payload; the
client library builds for macOS and iOS.

**Handshake.** `initialize {protocolVersion, clientInfo}` → `HostInfo {protocolVersion, hostID,
machineName, hostInfo, epoch, processID, startedAt, channel}`. `epoch` changes with every host
process; event numbers are comparable only within one.

**Sessions** (built):

| Method | Does |
| --- | --- |
| `_native/agents/sync {agents}` | the client's agent catalog, until the plugin registry moves into the host (Phase 3) |
| `session/list` | every session the host has open, as `HostSessionSummary` |
| `session/new {agentID, cwd, parentID?, origin, mcpServers}` | starts a session on an agent |
| `_native/session/open {agentID, agentSessionID, cwd, title?, mcpServers}` | adopts a session the agent listed; idempotent |
| `_native/session/attach {sessionID, epoch?, afterSeq?}` | replays the session's events as notifications, then answers; live events follow |
| `_native/session/detach`, `_native/session/close` | stop following; stop tracking (history stays with the agent) |
| `session/prompt {sessionID, requestID, text, behavior, echo, origin}` | → `prompted`, `steered` or `queued`, as soon as it's accepted. A repeated `requestID` gets the first answer and is never delivered twice |
| `session/cancel`, `session/set_config_option` | as in ACP |
| `_native/session/respond_permission {sessionID, toolCallID, optionID?}` | the first client to answer wins; the rest see it resolved |
| `_native/queue/update`, `…/remove`, `…/send_now` | edit the queue |
| `_native/activity/list {after?, limit}` | the activity journal, for "while you were away" |
| `_native/host/shutdown {stopAgents}` | stop for good, or restart once idle |

Notifications from the host: `_native/session/event {sessionID, event}`, `_native/session/changed
{summary}`, `_native/session/closed`, `_native/activity {entry}`.

**Events.** A session is an ordered log of `HostEvent`s numbered by `seq`. Agents' `session/update`
payloads travel **verbatim** (`update`), so every client folds them with the same ACP `SessionState`
reducer; Native's own facts are typed events: `reset(loading)`, `loaded`, `prompt` (agents don't
echo live prompts), `permissionRequested`/`permissionResolved`, `turnEnded`, `turnFailed`, `notice`
and `recovered`. `SessionMirror` folds a log into a transcript; the host keeps one per session too
(that's how it reads an agent's replay). Attach replays only what a client missed (same epoch,
`afterSeq`) or the whole log from its `reset`, as notifications before the response, like
`session/load`. So a client never misses or doubles an event, across reconnects and host restarts.
Unknown event types and enum values decode as `unsupported`/`unknown`, so an older client survives a
newer host.

**What the full UI needs on top** (designed; Phases 3 and 4), so the iPad runs the whole app against
a host:

| Area | Methods | Notes |
| --- | --- | --- |
| Commands | `_native/exec/run {executable, arguments, directory, stdin?, timeout?}` → `{exitCode, stdout, stderr}` | the host side is `Exec.LocalCommandRunner`; clients get a `RemoteCommandRunner: CommandRunner` that forwards, so Git and GitHub code runs unchanged wherever the project lives. Long output streams as `_native/exec/output` notifications |
| Files | `_native/fs/read {path, range?}`, `_native/fs/list {path}`, `_native/fs/stat` | paths are checked to be inside one of the host's projects |
| Change feed | `_native/fs/watch {root}` → `_native/fs/changed {paths}` | the host side of the Git package's `RepositoryMonitor`; coalesced like FSEvents |
| Usage and limits | `_native/usage/snapshot`, `_native/limits/changed` | the limits service and scheduled resumes move into the host |
| Host status | `_native/host/status` → memory, CPU, agent processes, keep-awake state, uptime | for the status bar and the hosts list |
| Agents | `_native/agents/list`, `_native/agents/restart`, `_native/agents/authenticate` | runtime status (`AgentRuntimeStatus`) as the host sees it |
| Orchestration, goals, workflows | `_native/tasks/*`, `_native/goals/*`, `_native/workflows/*` | engines run in the host; clients mirror |

## What the host stores

One SQLite database, `host.sqlite`, owned by the host and nothing else (system `libsqlite3`, no new
dependency). `journal_mode=WAL`, `synchronous=FULL`, `fullfsync=ON`, `checkpoint_fullfsync=ON`:
once a write returns it survives `kill -9` and power loss. Writes happen per user action and per turn
boundary, never per streamed token, so full syncs cost nothing noticeable. Why not an append-only
JSONL log: the state is small and mutable (queued messages edited and removed, sessions updated) and
needs multi-row transactions; a log would need compaction and replay code for every entity.

| Table | Holds |
| --- | --- |
| `meta` | host id, last heartbeat, boot time of the last run, clean-shutdown mark |
| `agents` | the agent catalog (`AgentSpec` JSON) the host launches from |
| `sessions` | open sessions: host id, agent and agent session id, cwd, parent, origin, title, last activity, last stop reason, queue paused, MCP servers to hand over on reload |
| `turns` | the unfinished turn per session: request id, text, kind (prompt or recovery), echo, start time, recovery attempts |
| `queue` | queued messages in order, with a steering-in-flight flag |
| `requests` | prompt request ids and what they became (pruned after 7 days) |
| `approvals` | permission requests waiting on the user, as facts |
| `activity` | the journal: turns finished or failed, approvals asked, recoveries |

Phase 3 adds `tasks` (the orchestration graph), `goals`, `workflow_runs`, `resumes` (scheduled limit
resumes), `unread` and `titles`, all owned by their engines inside the host.

## Recovery

A turn is committed to `turns` **before** its prompt is written to the agent, and deleted when the
agent answers. So after any interruption, the host knows exactly which turns were cut off. Recovery
reloads the session from the agent (`session/load`), then `RecoveryPlanner` decides from the replay:

- **The prompt is among the agent's latest user messages** → the agent had started. ("Latest" is the
  last three: agents can record something after a prompt they were cut off on; Claude Code adds
  "[Request interrupted by user]".) Native sends a message
  marked as its own: "Your previous turn was interrupted because …. Check the current state before
  you continue (for example, re-read files you were changing), then carry on. If it was already
  done, say so briefly." Whatever the agent committed is in its history; nothing is re-run blindly.
- **The prompt isn't there** → it never arrived, so sending it again is safe.
- **Three recoveries of the same turn already failed** → pause, so a crashing agent can't loop and
  burn quota. The queue pauses too; the user's next message continues.

| Interruption | Detected by | What the host does | What the user reads |
| --- | --- | --- | --- |
| Agent process exits mid-turn | its stdout closes | restarts the agent, reloads, resumes or resends | "Claude Code stopped unexpectedly at 2:14 PM. Native restarted Claude Code and asked it to pick up where it left off." |
| Agent exits while idle | same | nothing until the session is used; then reloads quietly | nothing (nothing was lost) |
| Agent can't start again (uninstalled, signed out) | launch or `initialize` fails | keeps the turn committed, session `disconnected` with the reason; retries on the user's next message or the next host start | "Native couldn't restart Claude Code: <reason>" with the fix (install command, Sign in) |
| Host killed or crashed | unfinished turns at startup, same boot | launchd restarts it; it resumes every unfinished turn, then drains queues | "Native's background host stopped unexpectedly at 2:14 PM. …" |
| Mac restarted or logged out | boot time differs from the last run's | resumes at login | "Your Mac restarted at 2:14 PM while Codex was working. …" |
| The prompt never reached the agent | not in the replay | resends with the same request id | "Your message hadn't reached Codex yet, so Native sent it again." |
| A steer was in flight | queue item flagged steering | dropped if the replay has it, otherwise it goes out as the next message | the message shows once, where it landed |
| Permission request pending | it dies with the agent process | withdrawn; the agent asks again after resuming | the approval card disappears, then reappears from the agent |
| User cancels during recovery | `session/cancel` while recovering | recovery stops; turn ends as cancelled; queue pauses | "Stopped." |
| Client disconnects mid-turn | socket closes | nothing: the turn runs on; the client re-attaches from its last event | the finished turn, as if it never left |

The interruption time comes from the host's heartbeat (written every 30 s), so "at 2:14" is within
half a minute; for agent crashes it's exact.

**While you were away.** The activity journal records finished and failed turns, approvals asked,
and every recovery with its cause and action. When the app connects it asks for entries after the
last one it showed and, if there are any, opens with a summary: "While you were away: 3 tasks
finished, 1 needs approval, Claude Code stopped once and Native resumed it." Each line links to its
session. Recoveries also show inline in the transcript, where they happened.

**Approvals while away** (Phase 3). The host posts a notification for each approval with Approve and
Reject actions (the `UNNotificationCategory` carries the options' kinds); the action is handled by
the host itself, so it works with the app closed. The menu bar extra lists sessions needing approval.
Approvals stay in `approvals` so a restarted host can tell the user one was pending even though the
agent will ask again.

What durability doesn't fix: a context window that's full, a provider outage, or side effects a tool
call made outside the project (a deploy, an email). Those are surfaced, not hidden; the interruption
message asks the agent to check before acting again.

## Menu bar extra (Phase 3)

The host shows an extra while agents work or need approval: a count, then a menu of sessions
(working, needs approval, done since you looked), Open Native, Pause Keep-Awake, and Stop All Agents.
It hides when nothing is running. macOS 27 also flags apps that keep running after quit; the GUI
itself exits fully, and the host is listed under Login Items as Native, so what keeps running is
visible and attributable.

## Migration

Every phase ships with the app working and feature agents unblocked.

**Phase 1: host, store, protocol, one session end to end (done).** `Packages/NativeHost`: the portable
core (`HostCore`, `HostStore`, recovery, socket server), `NativeHostMac`, the protocol and
`SessionMirror`, `NativeHostClient` (reconnecting, iOS-compatible), the `native-host` binary (`serve`,
`attach`), and tests that kill the host and the agent mid-turn. The `NativeHostHelper` target, the
generated launchd plist and `SMAppService` registration. `native/Host/`: registration, connection and
a "Durable Sessions (Preview)" window, opt-in. Nothing else in the app changes.

**Phase 2: the app becomes a client** (models agent, against `NativeHostClient`). The public API of
`AppModel` and `SessionModel` stays as it is; their insides change:

1. `AgentRuntime` becomes host-backed: status, capabilities and auth methods come from the host
   (`_native/agents/list`); `start`/`restart`/`signIn` become host requests. The app stops spawning
   agents; `AgentProcess` is used only inside the host.
2. `SessionModel` keeps `state`, `phase`, `queuedPrompts`, `needsApproval` and every method. It holds
   a `SessionMirror` fed by the client's events and a `HostSessionSummary`; `send`/`submit` become
   `session/prompt` with a fresh request id (retried with the same id after a reconnect), `cancel`,
   `choose`, `setConfigOption` and the queue edits become their host methods. `clientID` is the
   `HostSessionID`, now stable across restarts.
3. `SessionStore` routes `NativeHostClient.events` instead of `AgentEvent`s; `SessionLauncher`
   calls `session/new` and `_native/session/open`. `SessionCatalog` keeps listing history through
   the host (`_native/agents/list_sessions`, which wraps the agent's `session/list`).
4. Plugins still supply agents (sent with `_native/agents/sync`) and per-session MCP servers (sent as
   JSON with `session/new`), so the plugin API is unchanged.
5. `LoginShell` moves to `UserShell` (already in the package); `native/Models/LoginShell.swift` goes.
6. ⌘Q quits only the client; "Quit Native and Stop Agents" and the attached-host fallback land.
7. The app shows connection states and the "while you were away" summary.

**Phase 3: engines move into the host**, one PR each, each keeping its client-side API: the
orchestration MCP server (so delegated tasks survive the app quitting), titles, notifications with
actions, limit resumes, goals and workflows, keep-awake, the menu bar extra, unread state. The
plugin registry's runtime side follows (the plugin API moves into a package both sides import).
Engines come to the host as packages, never as app-target files: goals, workflows and automations
link `Packages/Automation` (Foundation-only, Codable, pure state plus a `due(at:)` planner), and the
host implements its `AutomationHost` (start a workflow run, prepare a worktree, poll GitHub), with
runs persisted in the host's store.

**Phase 4: other machines.** Exec, files and the change feed in the protocol; the SSH transport and
remote provisioning; the paired network transport and the iPad app.

## Risks

| Risk | Mitigation |
| --- | --- |
| Agents launched by launchd see a bare environment | the host reads the login-shell environment (`UserShell.LoginShell`), as the app does today |
| Privacy prompts (Desktop, Documents) attribute to "Native Host" | the helper is named and signed as Native; `AssociatedBundleIdentifiers` ties it to the app; documented in onboarding |
| User disables background activity | detected via `SMAppService.status`; attached-host fallback, with an explanation |
| A host bug kills every session at once | crashes are recovered like any interruption; recovery is capped per turn; the tests kill the host on purpose |
| Host and agent die together, so turns are interrupted rather than continuing | accepted: the recovery message is cheap and honest. A per-agent stdio relay that outlives the host could make host crashes invisible later |
| An agent's launcher (`npx`) dies but the adapter it started lives on, still holding the pipes | seen in E2E: the turn simply finishes, since the host talks to whoever holds stdio. Phase 2 tracks each agent's process group (npm makes its own) and ends the whole group when the top process exits or the agent is stopped |
| Recovery prompts spend tokens | only turns that were actually running are resumed, at most three times |
| An agent stores the prompt transformed, or adds markers after it, fooling the replay check | the check accepts containment within the last three user messages; the worst case is a harmless "you were interrupted" for a prompt it never saw |
| The in-memory event log grows with long sessions | cleared on every reload; a cap that reloads from the agent instead of keeping everything can come later |
| Protocol drift between app and host versions | version handshake, unknown-tolerant enums and events, restart-when-idle updates |
