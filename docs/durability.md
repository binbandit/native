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
 │        notifications, menu bar extra, exec + files                   │
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
killing the host mid-turn under launchd: no adapters were left behind). The host also notes the
process group of every process an agent starts (npm puts its children in groups of their own) and
ends them all when the agent stops, crashes, or its launcher exits while the adapter holds on
(`AgentProcessGroups`: SIGTERM, then SIGKILL after 2 s); Quit Native and Stop Agents does it before
the host exits, so nothing an agent started outlives it. (The opposite failures are as bad: daemons from old versions piling up, or an
app that reads "daemon unreachable" as "gone" and starts a second copy of a running conversation.
The lock and the single launchd label make both impossible.)

**Start.** One setting decides it: Settings ▸ Background ▸ "Keep agents running when Native quits"
(`HostSessions`, the user default `NativeHostSessions`, one value for every channel). It's read at
launch, since a running session can't move between the app and a host; changing it offers Relaunch
Now. Before any session starts, `DurableHost.launch` decides where this run's agents live
(`HostPlacement`) and hands the connected client to `AppModel.connectHost(client:)`:

1. **Background.** The app registers the agent (idempotent; development builds start a session-only
   launchd job instead, see "Development builds") and waits up to 2 s for the socket. A login item
   that was stopped on purpose (Quit Native and Stop Agents) only starts at login or registration,
   so if nothing answered the app registers it afresh (a session job is kicked) and waits up to 8 s.
   The first registration makes macOS post "Background Items Added", naming Native; that's expected,
   and Settings ▸ Background says the host is listed as Native under Login Items.
2. **Attached.** If the user disabled Native under System Settings › Login Items › Allow in the
   Background (`status` is `.requiresApproval`), registration failed, or the socket never answered,
   the app starts the same helper itself as its child (`AttachedHost`, `--exit-with-parent`), which
   stops its agents when the app quits. We respect the user's choice rather than detaching anyway.
   The app restarts an attached host that dies (at most three times a minute).
3. **In the app.** If no host answers at all, agents run inside the app exactly as before Phase 2.

Either fallback is said once per kind of reason (`HostFallback`), above the detail column, with the
fix where there is one (Open Login Items); Settings ▸ Background keeps saying it, and a later launch
that runs in the background again resets it. If the user switches Allow in the Background off while
Native runs, macOS stops the host; the app notices on the reconnect, starts an attached host on the
same socket, and says so. With the setting off, a launch that finds a host left from when it was on
stops it with its agents (`shutdown {stopAgents: true}`) and unregisters it, so nothing the user
turned off keeps running and no conversation runs twice. Debug builds take `-nativeHostRefused YES`
to act as if Allow in the Background were off, to try the fallback.

**Quit.**

| Action | What happens |
| --- | --- |
| ⌘Q, closing the window | The app quits. The host and its agents keep working. (With an attached host or agents in the app, they stop with it, as before.) |
| Native › Quit Native and Stop Agents (⌃⌥⌘Q, `app.quitAndStopAgents`; listed while agents would outlive the app) | The app holds the quit (`HostQuitDelegate`, at most 3 s) while it asks the host to stop (`_native/host/shutdown {stopAgents: true}`): the host ends running turns as stopped by the user, stops agents, writes a clean-shutdown mark and exits 0, and launchd leaves it down. The next launch starts it again. |
| ⌘Q after turning "Keep agents running" off | Same as Quit Native and Stop Agents: the setting now says agents stop when Native quits. |
| Menu bar extra › Stop All Agents | Same as above, without opening the app. |
| Logout or shutdown | launchd sends SIGTERM; the host is killed with its agents. Next login it starts and resumes what was running (`systemRestarted`). |

**Updates.** The app and its host come from one bundle, so after an update the host keeps running
the old binary until it restarts. On connect the app compares builds (`CFBundleVersion`, the same
for both) with `HostVersionStatus` and shows `HostVersionNotice` above the detail column:

| Host vs app | What happens | What the user sees |
| --- | --- | --- |
| Same build | nothing | nothing |
| Older host, nothing running | the app asks it to restart (`_native/host/shutdown {stopAgents: false}`); it exits 75 right away and launchd starts the new binary | "Native's background host is restarting onto 1.4…", then nothing |
| Older host, tasks running | same request; the host exits 75 the first moment nothing is running | "Native updated to 1.4. Its background host switches over when your tasks finish." with **Restart Host Now** |
| Restart Host Now | `shutdown {stopAgents: false, immediately: true}`: the host exits 75 at once; the new binary resumes interrupted turns as `hostUpdated` | in each transcript: "Native's background host restarted at 2:14 PM to update. Native restarted Claude Code and asked it to pick up where it left off." |
| Newer host (an older copy of Native was opened) | nothing; the host stays | "This copy of Native (1.3) is older than its background host (1.4)" with **Check for Updates** |

The app asks each host process (each `epoch`) once. **The handshake is frozen**, so this works
across any two versions: `initialize`, the `protocolVersion` and `hostInfo` of its result
(`FrozenHandshake`, decoded before anything else), and `_native/host/shutdown` never change. A client
that meets an older protocol version sends the restart request before disconnecting
(`NativeHostClient.connectOnce`) and shows `incompatible(protocolVersion, host)`; meeting a newer one
it only shows the state. Either way it checks again every few seconds, so it reconnects once the
host is back on a matching binary.

**Login.** `RunAtLoad` starts the host at login. It resumes only sessions that were working (an
unfinished turn or a non-empty, unpaused queue); idle sessions load lazily when a client opens them,
so login never spawns a dozen agents for nothing.

**Sleep.** Keep Mac Awake belongs to the host (`HostKeepAwakeEngine`; IOKit in `NativeHostMac`'s
`MacPowerBackend`). The app hands it the user's policy (`_native/host/keep_awake/set`), the host
keeps it in `meta`, and holds what `caffeinate -i -s` would (no idle or system sleep; the display
only if asked) while the policy calls for it: While Agents Work as long as any session works
(`HostSession.isWorking`), On or a timer regardless. So a droid stays awake mid-task with no window
open, and after a restart. Off, the default, holds nothing, so a laptop behaves as before. When
agents run in the app instead, the app holds the same assertions itself (`native/KeepAwake`).
Closing a laptop's lid still sleeps it; on wake, agents whose network calls failed surface as
failed turns, which the queue and limit logic already handle.

## Development builds

Several agents build and run Native at once, from different DerivedData folders and checkouts
(Kite quicksaves snapshot one shared working tree, so checkouts differ by build folder, not by
branch). One global host would make them fight: an old binary serving a new app, two apps
registering one launchd label. So each Debug build gets its own **channel**: the plist generator
hashes `BUILT_PRODUCTS_DIR` into `NATIVE_HOST_CHANNEL`, the label becomes `<bundle id>.host.<channel>`,
and the host lives in `~/Library/Application Support/Native/Channels/<channel>/`. The app reads the
channel from its own embedded plist, so app and host always agree. Native uses no channel and the
standard location; Native Nightly sets `NATIVE_HOST_CHANNEL = nightly` (`Config/Nightly.xcconfig`), so
its label is `<id>.host.nightly`, its host lives in `Channels/nightly/`, and the two installs never
share a socket, store or lock. The plist also carries `NATIVE_HOST_DEVELOPMENT=1` for Debug builds,
which is what makes a host a development host (named channels like `nightly` are real installs).
Host state (socket, database, lock) never lives in the repo tree.

Development hosts must not pile up, so they differ from release in three ways:

- **No login items.** A Debug build runs its host as a launchd job for the current login session
  only (`LaunchdSessionJob`: `launchctl bootstrap gui/<uid>` with a plist written to the channel
  folder). launchd still restarts it after a crash, but it never appears under Login Items, never
  triggers "Background Items Added", and is gone after logout. Only release builds use
  `SMAppService`. A Debug build that finds a login item left by an earlier build of itself
  unregisters it, from the owning app as `SMAppService` requires.
- **Idle exit.** A development host stops after 15 minutes with no clients and nothing running,
  unless devices are paired with it (`HostCore.hasPairedDevices`, which the helper keeps from its
  gateway): they reach it only while it runs.
- **The same switch.** Settings ▸ Background decides for development builds too, on by default
  like everywhere else. Turning it off stops the build's host and its agents and unloads the job at
  the next launch.

Every isolated instance (`scripts/dev/run-isolated.sh <name>`) builds into its own folder, so it
has its own channel, launchd label, socket and store: instances never share a host. The script
prints the instance's channel; `--quit` boots out its job (its running turns resume at the next
launch, as after a logout) and ends any host the app started itself (those turns end as stopped);
`--reset` and `--remove` do the same and delete its channel folder.

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

**Any machine can be a host.** The host core (`NativeHost`) builds wherever Foundation does; macOS
specifics (code signatures, boot time, FSEvents, keep-awake, the on-device title model, updating
itself) live in `NativeHostMac`. `native-host` builds on Linux without it: `LinuxHost`, in the
executable, gives the machine's name, its boot time from `/proc/stat` and the user's login-shell
environment. The Linux workflow (`.github/workflows/linux.yml`) builds it for x86_64 and arm64 in
`swift:6.4` and runs ACP's and the host's tests there; it reports without blocking until it's been
green on main. On Linux today:

- **The same as on a Mac:** sessions, turns, recovery and the store (the system SQLite:
  `libsqlite3-dev` to build, `libsqlite3` to run), the local socket and `attach`, agents in their own
  process group and ending every group their children moved into (from `/proc`), running clients'
  commands (`_native/exec/*`, so Git on an iPad works against the box), polling file watches.
- **Different:** no code-signature check of peers, so, as for a Mac development build, the user is the
  boundary (the socket's folder is theirs alone). Prompt images go as they are only when they're PNG
  or GIF already within the limits, since nothing scales them; anything else goes by path. npx always
  runs as npx (finding its install folder takes SHA-512). Logs go to stderr.
- **Mac only for now:** plugin assets (their content hashes are SHA-256: a client asking gets "Plugin
  assets aren't available on this host yet"), updating itself (Ed25519), Native's tools for agents
  (the MCP server is on Network, its tokens are HMACs), attached hosts (`--exit-with-parent` watches
  the parent with kqueue), on-device titles and `native-host doctor`. The cryptography comes with
  swift-crypto, deferred until Linux is a real target (docs/decisions.md, "swift-crypto for Linux
  hosts, deferred").

Every transport implements `HostTransport` and yields a `ByteStream`:

| Transport | Reach | Authentication | Status |
| --- | --- | --- | --- |
| `LocalSocketTransport` | this Mac | uid + code signature | built |
| SSH bridge: `ssh <machine> native-host attach` | a Mac mini, a Linux box | the user's own SSH keys; the bridge runs as that user on the remote host | the `attach` side is built; the client's process transport is next |
| Paired network transport | iPad, iPhone, another Mac on any network | QR pairing, then Noise (XX, then IK) with pinned static keys | built (`Packages/NativeLink`; Noise XX / XXpsk3 over TCP, see docs/companion.md) |
| WebSocket + TLS | cloud sandboxes | provider-issued token + pinned key | later |

**Pairing** (shared with the companion, `docs/companion.md`). The Mac shows a QR code carrying the
host's static public key, a one-time pairing secret (valid 5 minutes, single use) and its addresses
(LAN, Bonjour name, Tailscale name). The device connects, runs a Noise handshake that proves the
secret, and both sides pin each other's static keys. Every later connection is mutually
authenticated with those keys, so the network, Wi-Fi or a relay is never trusted. Paired devices are
listed in Settings with a last-seen time and can be revoked; a revoked key is refused at the
handshake. Bonjour finds the host on the LAN; a Tailscale name or a ciphertext-only relay reaches it
elsewhere (open question in the companion doc).

**Pairing a host without a screen** (a Mac mini in a closet). `"Native Host" pair`, run in a shell
on it (`<Native.app>/Contents/Library/LoginItems/Native Host.app/Contents/MacOS/Native Host pair`),
opens a pairing window through the gateway's control socket and prints the same kind of link: the
host's key, name and addresses (LAN, Bonjour, the Tailscale address and its MagicDNS name), and the
grants the pairing gives. It waits until a device pairs or the link expires (5 minutes, single use),
says which, and the window closes when it exits. Nobody sits at the host to confirm, so whoever runs
`pair` decides up front: the device that proves the link's secret pairs at once with no more than
those grants and what the device asked for, and the typed code is refused for such a window
(`LinkGateway.openPairingWindow(preapproving:)`, `LinkPairCommand`). Any process running as that
user can run `pair`, a coding agent following a hostile repository's instructions included, so it
gives only sessions unless asked (`--run-commands`, `--install-updates`, `--manage-plugins`), and
every pairing, on screen or not, goes into the host's activity journal (`devicePaired`, naming the
device, how it paired and what it may do) and to every connected client. Add Host on a Mac
(`native/Hosts/AddHost*`) pastes the link, or runs `pair --json --run-commands --install-updates
--manage-plugins` over the user's own SSH (BatchMode, never prompting), shows what the link offers
with a checkbox each (commands and updates on, plugins off), and pairs with what the owner keeps.
The pairing remembers the SSH destination. Only the embedded helper has `pair`: a host without it
(Linux, later) needs `native-host` moved into a package that depends on both NativeHost and
NativeLink, with its `serve` starting a `LinkGateway`.

**Plugins reach every client** (docs/decisions.md, "Plugins live on hosts and reach every client").
Host-side contributions (agents, MCP servers, engines) run on the host; client-side data (themes,
icon sets, celebrations, experiments) travels as manifests and assets. `NativeHostClient.PluginAssets`
keeps each host's assets on the device by content hash, so a client that synced once shows them
offline. Built-in plugins ship in every binary and aren't sent.

**What a client may do.** Every client follows and drives tasks. Beyond that, each connection
carries `ClientGrants`, and what a grant allows is checked twice: by the `NativeLink` gateway before a
paired device's request reaches the host (`LinkMethodPolicy`, which refuses anything it doesn't list),
and by the host itself. Local clients (same uid and, in signed builds, the same team) and the SSH
bridge (`native-host attach` reaches the socket as that user, who could run anything anyway) are the
owner and hold every grant. Paired devices hold what their pairing grants, changeable on the Mac; a
revoked device is cut off at its next handshake. No unauthenticated listener ever opens on a network
interface. Approvals given from a device are recorded in the transcript as coming from that device.

| Grant | Who holds it | What it allows |
| --- | --- | --- |
| none | every paired device | `initialize`; `session/list`, `new`, `open`, `attach`, `detach`, `prompt`, `cancel`, `set_config_option`, `respond_permission`, `respond_question`, `run_hidden`, `close`; the queue's `update`, `remove`, `restore`, `move`, `send_now`; `activity/list`; `agents/list`, `start`, `authenticate`, `check_sign_in`, `cancel_sign_in`, `list_sessions`; `host/status`, `host/doctor`, `host/update/status` and `check`; `plugins/list` and `asset`; `notifications/list`, `acknowledge`, `act`; `session/set_title` |
| `managePlugins` | the owner; devices whose pairing grants it | `plugins/set_enabled` |
| `manageHost` | the owner; devices whose pairing grants it (offered on for a device that paired with the invite) | `host/update/install`, `host/keep_awake/set`, `agents/credentials/set` and `remove`, `titles/configure` |
| `runCommands` | the owner; devices whose pairing grants it (offered on only for a Mac that paired with the invite; off for phones and iPads, and for pairings from before it existed) | `_native/exec/*`, `_native/fs/*`, `_native/projects/*`, `session/set_mcp_servers`, `agents/sync` (an agent's spec is a command; a headless host's catalog comes from the Mac driving it, whose `worktreesFolder` is ignored); `session/new` and `open` with a stdio MCP server or any `_meta`; `activity/list` with `includeCommands` |
| `isLocal` | the owner only, never over a link | `host/shutdown`, `host/update/report`; `agents/sync`'s `worktreesFolder` |
| nobody over a link | | `agents/stop`, `restart`, `delete_session` |

**Running commands is remote code execution, by design.** It's what lets a laptop run git and gh in a
checkout on a Mac mini, and why `runCommands` is a grant of its own, never implied by another and never
held by a phone unless its owner turns it on. What it covers:

- `_native/exec/run` runs any executable as the host's user. A command's folder, and every path the
  file requests take, must resolve inside one of the host's roots once every symbolic link, `.` and
  `..` is resolved (`ProjectPaths`): a project listed with `_native/projects/add`, the folder of a
  session the host has, or the task worktrees folder (`~/.native/worktrees`, or where the Mac app
  moved it, sent with `agents/sync`). A path that doesn't exist yet resolves through its nearest
  existing folder; a dangling link, or `..` past a missing folder, is refused. Files are opened with
  no link followed anywhere in the path (`O_NOFOLLOW_ANY`; the last component only, off Darwin), so a
  link swapped in after the check can't lead out. Projects are never `/` or the home folder itself.
- That boundary keeps the file API and commands' folders where the client means them. It isn't a
  sandbox: a command reads whatever the host's user can. The grant is the boundary.
- An agent starts commands too: a stdio MCP server is one, and agent options in `_meta` (hooks,
  servers, executables) can name more. So a session request carrying either takes `runCommands`
  (`HostProtocol.sessionRequestRunsCommands`); MCP servers reached over HTTP or SSE don't.
- What it doesn't cover: a device that drives tasks can still ask an agent to run something, and
  approve the agent's permission request. That shows in the transcript, as from that device, and goes
  through the agent's own permission rules.
- Every command is journaled before it runs (`ActivityEntry.Kind.commandRun`: the client's name,
  the command line, its folder). A command whose record can't be written doesn't run. These entries
  aren't sent as `_native/activity` and `activity/list` leaves them out unless asked
  (`includeCommands`, which takes the grant), so a day of `git status` never buries what happened to
  tasks; they're kept 30 days.

**Updating a host remotely.** Any authenticated client may read a host's update status
(`_native/host/update/status`, `check`, and the `changed` event). Installing
(`_native/host/update/install {when: idle | now}`) is allowed only for local clients (same uid and,
in signed builds, the same team), clients over the SSH bridge (that user could replace the binary
anyway), and paired devices whose pairing allows managing the host (on by default for devices paired
by QR from that Mac; revocable per device in Settings). There is no unauthenticated way to reach it,
because no unauthenticated listener exists. The request carries no URL, version or binary: the host
installs only what its own check found in its own feed, verified with the public key compiled into
it, and only a build newer than the running one. So the worst a compromised device can do is start
the install of a genuine signed release, or restart the host. `when: now` interrupts running turns
and is sent only after the user chose "Install Now, Interrupt Tasks" on the device; `idle` waits.
Every install request goes into the activity journal with the device that sent it. The provider,
status shape and install flow are in `docs/releasing.md` ("Remote updates").

How the host enforces it (`HostCore+Updates.swift`, `HostCore+Clients.swift`,
`HostCore+ExecAccess.swift`; tests in `HostUpdateTests`, `HostExecTests`, `ProjectPathsTests` and
NativeLink's `PairingTests` and `CommandGrantTests`): each connection carries `ClientGrants {managePlugins, manageHost,
isLocal, runCommands}`. The socket's own clients and SSH bridges are the owner (all four); paired
devices come through the `NativeLink` gateway with `isLocal: false` and what their pairing grants
(`LinkGrants`), per the table above. The gateway applies the table before forwarding, and the host
checks again. The provider comes from where the host runs (`MacHostUpdates`): inside
Native.app it relays installs to the app (`_native/app/update/install`, or `open -g -j Native.app
--args -NativeInstallUpdateAndQuit YES` when no app is connected) and restarts once its own bundle's
`CFBundleVersion` on disk changes (now if a device asked for now, else when idle); under
`~/.native/host/versions/` it updates itself with `Packages/HostUpdater` (startup check and rollback,
a self-handshake before `confirm`, a feed check every 24 hours).

**Native's MCP server across launches** (Phase 2; with `NativeHostTasks` on, the host serves the
tools instead, see "Native's tools in the host").
The app serves the orchestration MCP server, and a host session keeps the URL it was first handed:
the host stores each session's MCP servers and gives them to the agent at every `session/load`. So
the URL outlasts the app:

- **The port** is remembered per channel and reused when it's free. The server waits up to five
  seconds for it (a relaunch opens the new copy before the old one quits), then takes any free port.
- **The token** in `/mcp/<token>` is `<HostSessionID>.<HMAC-SHA256>`: a MAC over a versioned string
  holding the channel and the session's id (`SessionContext.clientID`, stable for host sessions),
  keyed by a 256-bit secret from the system's CSPRNG. The secret lives in
  `~/Library/Application Support/<bundle id>/Orchestration/<channel>/token-secret` (folder `0700`,
  file `0600`, created exclusively and then renamed into place; one with looser permissions or
  another owner is replaced). The server checks the MAC in constant time (CryptoKit), then resolves
  the id to a session the app has open or the host runs; anything else gets 404. Neither the secret
  nor any token is logged. `MCPTokenSigner`, `MCPServerStore` and
  `MCPHTTPServer.start(remembering:scope:tokens:)` in Packages/MCPServer, with tests there.
- **When the port is taken**, the server moves and replaces the secret before it listens anywhere.
  Every launch, once the host is connected, the app hands each host session its current URL
  (`_native/session/set_mcp_servers` with `replacingNamed`, which upserts the `native` entry and
  writes nothing when it's unchanged), so the next load brings the tools back, also for sessions
  from before URLs lasted. A session loaded right now keeps the old address until it reloads; after
  a move, `OrchestrationServerNotice` says so once and offers Restart Host.

What this changes in the threat model. Before, tokens were 256 random bits per session per launch,
held only in memory, and worthless once the app quit. Now a token lasts as long as the install's
secret and the session. Unchanged: the server listens on loopback only and refuses requests with an
`Origin` or a non-loopback `Host` (DNS rebinding); every request is authenticated by its token;
tokens can't be guessed. Secrets are per install and per channel, and the channel is signed too, so
no token works for another install or channel. New, and how far it goes:

- **A secret on disk.** The user's own processes can read it, as they can already read
  `host.sqlite`, which stores every session's MCP URL, and as they can run agents themselves: the
  user account is the boundary, as for the host socket in development builds. Other users can't.
- **A captured token stays useful.** Agents send their tokens to whatever listens on the remembered
  port. Another user's process that takes that port while Native is closed, and is called by an
  agent in the host meanwhile, learns those tokens. If it still holds the port when Native starts,
  the server moves and retires the secret, so they never work again. If it lets go first, they work
  until the secret changes: accepted for Phase 2, and closed when the host serves the tools and holds
  the port whenever agents run ("Native's tools in the host"). A token stops working when the host closes its
  session, and deleting `token-secret` retires every token (sessions get new URLs at the next launch).

## Host identity and many hosts

Each host has a `HostID` (a UUID kept in its store) and a machine name, returned by `initialize`. A
session belongs to exactly one host: `(HostID, HostSessionID)`. A project doesn't: it's a
repository, and each device has its own checkout of it.

**Hosts in the app** (`native/Hosts/Model/`, `AppModel+Hosts*.swift`). Besides its own host
(`DurableHost`, over the local socket), the Mac keeps one `RemoteHost` per paired host in
`RemoteHosts` (`model.hosts`), each with its own `NativeHostClient` over NativeLink
(`PairedHostTransport`: Bonjour by key fingerprint, then the addresses it paired with, each with the
mutually authenticated handshake). A pairing is remembered as one file per host
(`FilePairedHostStore`, `~/Library/Application Support/<bundle id>/Hosts/<HostID>.json`, `0600` in a
`0700` folder) holding the host's pinned key, its addresses, the grants it gave and this Mac's key
for that host alone; the keychain would prompt on every development build's new signature, so the
folder is the boundary, as for the host's own key. The client lives as long as the pairing and
reconnects by itself, so session models made on it survive drops, sleep and host restarts. Each
`RemoteHost` mirrors the host's agents as `AgentRuntime`s (the same status, capabilities and
sign-in methods every agent row shows), its open sessions, a connection log and "while you were
away" from its journal (`HostSeenActivity` keeps the last entry seen per `HostID`, for this Mac's
host and every paired one). Bonjour browsing, which is what asks for local-network access, starts
only once a host is paired. Remote hosts are off by default until they work end to end
(`-NativeRemoteHosts YES`, or that user default).

**Projects across devices.** `Project.url` is this Mac's checkout; `Project.checkouts` holds one
`ProjectCheckout {host, path}` per paired host; `Project.repository` is the hosted repository the
checkout's `origin` names ("github.com/owner/name", read by `ProjectRepository`, which folds every
spelling git takes), and `remoteURL` is that remote as this Mac has it, to clone from. A host's
checkout is found by repository, never by path: on connect the app lists the host's projects
(`_native/projects/list`) and reads each one's remote with `Git` over `RemoteCommandRunner`. A
project without a hosted remote is the same project on another device only where the user sets its
folder there. Sessions are keyed as on this Mac (`SessionKey`: agent and agent session id), and
`AppModel.remoteSession(_:)` says which host holds one; the sidebar keeps grouping by project and
lists each project's sessions on paired hosts beside this Mac's (`remoteSessionSummaries`: what the
host has open in its checkout, then what its agents saved there), with a device badge.

**New session on a device.** The device picker (`AppModel.deviceOptions(for:)`) lists This Mac and
each paired host with its availability (online, connecting, or offline with the reason) and the
project there: a checkout, `willClone` (the host can run commands and the project has a remote),
or `cannotClone` with why. It defaults to the device last used for the project while it can take
a session (`preferredDevice`). Starting on a host lists a starting task at once, as on this Mac,
then clones the project when the host has none (`_native/projects/add {create: true}`, then `git
clone` there), makes the task's worktree there as on this Mac, starts the agent on the host and
opens the session in the worktree. Failures stay on the task with Retry, and a task that hasn't
had a message moves to another device from the picker with its draft (`moveNewTask`).

**Hosts in the UI** (`native/Hosts/Components/`, `native/Hosts/Settings/`). Each device has a look:
a symbol and one of the app-icon palettes as its color (`HostLook`), kept on this Mac by device
(`HostLookStore`), so a removed host keeps it when it's added again. The picker is
`HostDevicePicker` behind a `HostDevicePill` (↑ ↓ Return, digits, Escape; docs/keyboard.md), and a
session on another device carries a `HostDeviceBadge`: the device's glyph on a sidebar row, glyph and
name in the session header, with the state only while it isn't online. Settings ▸ Hosts lists This
Mac and every paired host: its connection state (with the reason and Try Now while it's offline,
what to update when versions differ, Pair Again when the host ended the pairing), what it runs on
(system, Native version, uptime, load and whether it stays awake, from `_native/host/status`), its
tasks, and its agents with whom each is signed in as. A host can be renamed, given another look,
or removed: the confirmation says its tasks keep running there but leave this Mac's sidebar, and
Undo puts the pairing back. An agent on a host signs in there, so a method that opens a browser
would open it on the host's screen: the sign-in sheet leads with a key (kept in the host's
keychain, with Remove) or a link and code to open on any device, then the exact SSH steps
(`ssh <destination>`, then the agent's own terminal sign-in) and Check Again, and offers the browser
method last. The page shows only while remote hosts are on; in development builds
`-NativeHostsFixtures all|empty|signin|components` shows it with made-up hosts.

**A host's tasks, like this Mac's.** Each paired host gets its own `GitStore` whose git runs on the
host (`Git.onHost`: `RemoteCommandRunner`, the host's login-shell environment, and its change feed
for watching) and keeps worktrees in the host's `worktreesFolder`, wrapped in the same
`GitTaskWorkspaceProvider` (`RemoteHostsWiring`). `DeviceTaskWorkspaces` is the app's task
workspaces while remote hosts are on: it sends archiving, restoring, deleting and branch renames to
the host whose worktrees folder or checkout holds the task's folder, so a task on a host is put away
with its checkpoint there exactly as one here. Deleting a task's copy in its agent and pinning use
the host's runtime (`agentRuntime(for:)`). What a host's sessions get from this Mac: its agent
catalog (`_native/agents/sync` with the plugin-built specs, on each connection with `runCommands`,
never this Mac's worktrees folder or a command that's a path here), its organization policy as
`_meta`, and only MCP servers the host can reach itself (`PairedHostServers`: HTTP to another
machine); this Mac's loopback tools and stdio commands stay here. Task setup and teardown scripts
don't run on hosts yet.

**Testing against a second host on this Mac.** With one Mac, a second isolated instance's host is
the stand-in droid: its own channel, store, gateway key and port, reached over NativeLink on
127.0.0.1 exactly as a Mac mini is reached over the LAN (the same Noise handshake, pinned keys,
grants and method policy). `-NativeRemoteHostsLoopbackOnly YES` (Debug only) keeps the laptop
instance to loopback with no Bonjour, so no local-network prompt appears. Two differences from a
real droid are worth knowing: both hosts' agents share this Mac's agent stores, so the droid's
checkout must be a different folder from the laptop's (agents list by folder); and quitting the
laptop instance only stands in for closing the lid while the droid's host keeps running on its own.

**Connection states** (`NativeHostClient.ConnectionState`; a paired host adds `pairingEnded`
in `PairedHostPhase`), each with its own UI:

| State | Meaning | What the user sees |
| --- | --- | --- |
| `connecting` | first attempt | at launch, before any session starts, behind the launch screen |
| `connected(HostInfo)` | handshake done | normal |
| `reconnecting(attempt, reason)` | the connection dropped; retrying fast (100 ms, then 0.5–2 s) | "Reconnecting…" in the status bar, with a loader; prompts can still be typed and are sent with their request ids once back |
| `connected` with a new `epoch` | the host process restarted (a crash, an update, Restart Host) | "Host restarted" in the status bar for 30 s; its popover says why and what resumed: "Native's background host stopped unexpectedly and started again at 2:14 PM. It resumed the task that was working." |
| `unreachable(reason)` | four failures in a row; retrying every 5 s | "Host not responding" in the status bar; after 15 s (longer than launchd takes to restart a crashed host) also a notice above the detail column, since the status bar can be hidden, with Restart Host and the reason. For a remote host (Phase 4), the SSH command that failed |
| `incompatible(hostVersion)` | protocol mismatch | `HostVersionNotice`: "Update Native on <host>" (remote) or "Restart the host" (local) |
| `pairingEnded(LinkError)` (paired hosts) | the host revoked or forgot this Mac, or can't prove its pinned key | the client stops retrying; the host is offline in the picker and its page with the host's own words ("This device was removed on the Mac. Pair again to reconnect.") |

The status bar item (`HostConnectionStatusItem`) shows only while something is off. A local host
restarting under launchd is back within one launchd throttle interval (10 s), usually under a
second, so after a host crash the app shows `reconnecting` briefly, then "Host restarted" and the
recovered sessions. Restart Host registers the job afresh (a session job is kicked), or starts an
attached host again.

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
own are `_native/*`. `HostProtocol` in `NativeHostProtocol` defines every method and payload (one
file per area: `HostRequests`, `HostAgents`, `HostActivity`, `PromptEcho`); the client library
builds for macOS and iOS. `HostProtocol.version` is 2 since Phase 2.

**Handshake.** `initialize {protocolVersion, clientInfo}` → `HostInfo {protocolVersion, hostID,
machineName, hostInfo, epoch, processID, startedAt, channel}`. `epoch` changes with every host
process; event numbers are comparable only within one.

**Agents** (Phase 2). The host runs every agent; clients see and steer them through it.

| Method | Does |
| --- | --- |
| `_native/agents/sync {agents, refreshEnvironment, worktreesFolder?}` | the client's agent catalog (plugins still supply agents), until the plugin registry moves into the host (Phase 3). `refreshEnvironment` reads the login shell's environment again for agents started from then on (after an install or a sign-in in a terminal). `worktreesFolder` is where the local app makes task worktrees, when it moved them. Local clients, and devices with `runCommands` (their `worktreesFolder` is ignored) |
| `_native/agents/list` | → `[HostAgent]`: `state` (`stopped`, `starting`, `ready`, `failed`, `notInstalled`), `problem`, the agent's `initialize` result verbatim while it runs (info, capabilities, sign-in methods, steering), `processID`, `launchedSpec` (to tell when a changed spec needs a restart), `needsSignIn`, `isSigningIn`. An agent that exits on its own is `stopped`, not `failed`: it starts again on demand |
| `_native/agents/start {agentID}` | starts it unless running; answers with how that went (a failure is its state, not an error). Callers share one launch |
| `_native/agents/stop {agentID}` | → `{stopped, agent}`; refuses while one of its sessions is working (a turn, a recovery, a retry, a hidden command, a queue waiting to go out) |
| `_native/agents/restart {agentID}` | stops it and starts it on its current spec; turns it was running recover with the cause `agentRestarted` ("You restarted Codex at 2:14 PM. Native asked it to pick up where it left off.") |
| `_native/agents/authenticate {agentID, methodID}` | ACP `authenticate`; the agent may open a browser and wait. Any request the agent turns away with `auth_required` sets `needsSignIn` |
| `_native/agents/list_sessions {agentID, cwd?, cursor?}` | ACP `session/list`, verbatim (`ListSessionsResponse`), starting the agent if needed |
| `_native/agents/delete_session {agentID, agentSessionID}` | ACP `session/delete`; a host session holding it is closed too |

`_native/agents/changed {agent}` follows every change. Agents launch without npm in the middle when
npx has the exact version installed (`AgentCommand.skippingNpx`), and are told the client answers
form questions (`elicitation`), as the app's own `InitializeRequest` says.

**Sessions.**

| Method | Does |
| --- | --- |
| `session/list` | every session the host has open, as `HostSessionSummary` |
| `session/new {sessionID?, agentID, cwd, parentID?, origin, mcpServers, meta?, attach}` | starts a session on an agent. The client may choose the id (it's `SessionContext.clientID`, which plugins key per-session MCP servers by before the session exists); an id the host has returns that session, so a retry never starts two. `meta` is the `_meta` for `session/new` and every `session/load`. With `attach`, the caller follows the session from its first event |
| `_native/session/open {sessionID?, agentID, agentSessionID, cwd, title?, parentID?, origin, mcpServers, meta?, attach}` | adopts a session the agent listed, replaying it with `session/load`; an agent session already open returns its host session without a reload. With `attach` it answers as soon as the session exists (phase `loading`) and the replay streams in; a load that fails leaves it `disconnected` with its `problem` and a "Couldn't load this session" notice. Without, it answers after the load and a failure throws |
| `_native/session/attach {sessionID, epoch?, afterSeq?}` | replays the session's events as notifications, then answers; live events follow |
| `_native/session/detach`, `_native/session/close {sessionID, closeInAgent}` | stop following; stop tracking (history stays with the agent), and with `closeInAgent` free it in the agent's process (`session/close`) |
| `_native/session/set_mcp_servers {sessionID, mcpServers, replacingNamed}` | the MCP servers the agent gets at the session's next load (a loaded session keeps its own): the whole list, or with `replacingNamed` an upsert by name that leaves other servers alone. Nothing is written when nothing changed. For servers whose address changed since the session opened (Native's orchestration server after a port fallback) |
| `_native/session/set_title {sessionID, title?, source}` | `source: user`: the user's own title, from any client; nil or empty goes back to the automatic one (undo). `source: generated`: a title a client wrote because the summary's `titles.request` asked for it; the first generated title stays. See "Titles" |
| `_native/titles/configure {provider, instructions}` | who writes titles (`on-device`, `client`, `off`) and the user's title instructions, kept in the store so they hold with no client attached. The owner, or a device allowed to manage the host |
| `session/prompt {sessionID, requestID, text, content?, attachments, preamble?, behavior, echo, origin}` | → `prompted`, `steered` or `queued`, as soon as it's accepted. A repeated `requestID` gets the first answer and is never delivered twice, also while the first is still being handled; `NativeHostClient.prompt` resends it by itself after a dropped connection. `content` is the ACP blocks to send (attachments, images, linked files); `text` is what the transcript shows and what recovery looks for in a replay. `preamble` (a mode's instructions) goes ahead of the message unless the agent's last delivered preamble has the same id |
| `session/cancel {sessionID}` | asks the agent to stop (`isStopping` in the summary). If it hasn't confirmed after 10 s, or the user asks again more than a second later, the host ends the turn itself ("Codex didn't confirm it stopped, so Native stopped waiting…") and ignores the late answer. Cancels a pending retry instead, if there is one. On an agent's own subagent it cancels just that subagent's work |
| `session/set_config_option {sessionID, configID, value}` | as in ACP; the host remembers the value and sets it back after any reload where the agent reports another (codex-acp reopens on its default model) |
| `_native/session/respond_permission {sessionID, toolCallID, optionID?}` | the first client to answer wins; the rest see it resolved |
| `_native/session/respond_question {sessionID, questionID, response}` | answers a form question (`elicitation/create`) with ACP's response verbatim; the first client wins |
| `_native/session/run_hidden {sessionID, text}` | → `{output}`: runs a command such as `/context` as a turn the transcript doesn't show (the reply is collected, late copies of it dropped). Only while idle; not a durable turn |
| `_native/queue/update`, `…/remove`, `…/restore {itemID, index}`, `…/move {itemID, before?}`, `…/send_now` | edit the queue. The host keeps the last 20 messages removed from each queue, so undo sends only the id. Send Now steers where the agent can, and otherwise stops the running turn and sends the message next |
| `_native/activity/list {after?, limit, includeCommands?}` | the activity journal, for "while you were away". The record of commands clients ran only with `includeCommands` (which takes `runCommands`) |
| `_native/notifications/list {after?, limit}` | → `{notifications, active, latestID}`: the notifications numbered after `after` (whatever their state), every one still news, and the newest id handed out. See "Notifications" |
| `_native/notifications/acknowledge {ids}` | the user saw these on this client; older active ones in the same groups go with them. Every client hears `cleared` |
| `_native/notifications/act {id, action, text?}` | → `{outcome}`: does what the user picked on a notification (`allow`, `reject`, `reply`) and acknowledges it. `done`, `alreadyAnswered` (answered elsewhere first), `openTask` (the notification can't do it; open the task), `expired` (older than the backlog) |
| `_native/plugins/list` | the host's installed plugins (`~/.native/plugins/<id>/plugin.json`), manifests verbatim, with on/off state; `_native/plugins/changed` follows any change |
| `_native/plugins/asset {pluginID, path, knownHash?}` | one file from a plugin's folder: its sha-256 and the data, or no data when `knownHash` is current. Paths can't leave the folder (symlinks resolved); 8 MiB cap |
| `_native/plugins/set_enabled {pluginID, isEnabled}` | needs the `managePlugins` grant: the owner (local and SSH clients) has it, paired devices only if their pairing grants it |
| `_native/host/shutdown {stopAgents, immediately}` | stop for good, or restart (once idle, or now) for an update. Frozen |
| `_native/tasks/list` | → `[HostTask]`: every task sessions handed each other through Native's tools, oldest first, with the host sessions running it and its parent while the host has them. See "Native's tools in the host" |
| `_native/tasks/configure {servesTools, disabledSkills, appTools}` | whether the host serves Native's tools (it does unless told otherwise), Native's skills switched off (everywhere or per folder), and the tools only this app answers. Kept in `meta`. Local clients only |
| `_native/tasks/app_tool_result {callID, result?, listing?}` | the app's answer to `_native/tasks/app_tool_call {callID, kind, tool, sessionID, agentID, cwd, arguments}`: a call's result, or the tool as it lists for that session. Local clients only |
| `_native/tasks/call_tool {sessionID, tool, arguments}` | → `{text, structuredContent?, isError}`: one of the host's own tools, called as that session (the app's `run_script` binds them). Local clients only |
| `_native/host/status` | → `HostStatus`: the system ("macOS 27.1"), model, boot time, 1-minute load average and keep-awake state. `_native/host/status/changed` follows about every 30 s while a client is connected, and at once when keeping awake changes |
| `_native/host/keep_awake/set {policy}` | the machine's Keep Mac Awake policy → `HostKeepAwakeState`; the owner, or `manageHost`. The host remembers it across restarts |
| `_native/host/doctor` | → `HostDoctorReport`: read-only checks of what the host needs to run agents on its own, each with its fix (docs/droids.md); also `Native Host doctor` and `native-host doctor` over SSH |

Notifications from the host: `_native/session/event {sessionID, event}`, `_native/session/changed
{summary}`, `_native/session/closed`, `_native/agents/changed {agent}`, `_native/activity {entry}`,
`_native/notifications/posted {notification}`, `_native/notifications/cleared {ids, state, by?}`,
`_native/host/status/changed {status}`, `_native/tasks/changed {task}` and `_native/tasks/app_tool_call`.

The summary carries what clients show without following a session: phase, `needsApproval`
(permissions or questions open), the queue (attachments without image data), `isQueuePaused`,
`isStopping`, `isRunningHiddenCommand`, `retryAt`, `lastStopReason`, `problem` and `titles`.

**Commands and projects** (Phase 4). With the `runCommands` grant ("What a client may do"), a client
runs commands on the host and tells it where its projects are, so code that takes a `CommandRunner`
(`Packages/Git`, `Packages/GitHub`) works unchanged against a checkout on another machine.

| Method | Does |
| --- | --- |
| `_native/exec/run {execID, executable, arguments, directory?, environment, stdin?, timeout?, stream}` | → `{exitCode, stdout, stderr}` (data as base64). Runs with the host's login-shell environment, `environment` set on top of it, in `directory` (inside a root). `execID` is the client's: it names the output and what `exec/cancel` stops. With `stream`, output goes out as `_native/exec/output {execID, stream, data}` as it arrives; without, the host still sends it ahead once more than 1 MiB waits, so no message grows with the output. Either way the result carries what wasn't sent: a command's output is its notifications, in order, then the result. Fails with `commandNotFound`, `timedOut` (the command and everything it started were stopped), `cancelled` or `outsideProjects` |
| `_native/exec/cancel {execID}` | stops a command this client started (its process group: TERM, then KILL after 3 s); its run fails with `cancelled`. A client that disconnects has its commands stopped the same way |
| `_native/projects/list` | → `{projects: [{path, addedAt}], worktreesFolder}`: the projects (resolved paths) and where task worktrees go on this host, so a client makes a remote project's worktrees there |
| `_native/projects/add {path, create}` | lists a folder as a project, idempotent; `create` makes it first, for a clone (`projects/add`, then `exec/run git clone … .`). Never `/` or the home folder itself |
| `_native/projects/remove {path}` | stops listing it; nothing on disk changes |

On the client, `RemoteCommandRunner: CommandRunner` (`NativeHostClient`) forwards: it collects the
output notifications (through `HostNotificationRoute`, which gives one method's notifications to one
receiver in order with the client's events), cancels on the host when its task is cancelled, and fails
the way `LocalCommandRunner` would (`CommandError.notFound`, `.timedOut`, `CancellationError`), plus
`.unavailable` when the host isn't connected or drops mid-command and `.refused` when the grant or a
root says no. A remote `Git` is built with `environment: [:]`, so nothing of the client's PATH or HOME
travels. The host takes its runner from `HostCore.Configuration.commands`, `LocalCommandRunner` by
default on macOS and Linux (`Process` and `kill(2)` only; on Linux, where a pipe can't be told not to
raise SIGPIPE, the process ignores the signal). Elsewhere the core compiles without one and answers
that it can't run commands.

**Files and the change feed** (Phase 4). With the same grant, a client reads a project's files and
watches it, so diffs, Files Changed, file mentions and live git status work for a checkout on another
machine. Paths must resolve inside a root exactly as commands' folders do (`ProjectPaths`), and errors
name the path as the client sent it.

| Method | Does |
| --- | --- |
| `_native/fs/read {path, range?: {offset, length}}` | → `{data, size, modifiedAt}` (data as base64; `size` is the whole file's). One answer carries at most 1 MiB (`FileReadResult.sizeLimit`), so a slow connection's other traffic never waits long behind a file: a bigger file read without a range fails with `fileTooLarge` (its size and the limit in the error's data), a longer range with invalid params. A range past the end reads what's there. Reads run off the host actor. Fails with `fileNotFound`, `notAFile` (a folder, pipe or device, never opened) or `outsideProjects` |
| `_native/fs/list {path}` | → `{entries: [{name, kind, size, modifiedAt}], isTruncated}`, sorted by name, the first 10,000. Entries are as they are in the folder: a link is a `symlink`, never followed. `notADirectory` on anything else |
| `_native/fs/stat {path}` | → `{path, kind, size, modifiedAt}`, links followed (inside the roots); `path` is where it led |
| `_native/fs/watch {watchID, root}` | sends `_native/fs/changed {watchID, paths, isOverflow}` for a folder, `paths` relative to `root` as the client spelled it ("" is the folder itself). Coalesced like FSEvents: the first change after a quiet spell goes out at once, later ones at most every 200 ms, merged. More than 1,000 paths, a path the host can't place under the root, or a watcher that lost track (FSEvents' must-scan, dropped events, the root moving) is `isOverflow` with no paths: look at everything again. `watchID` is the client's, so it routes changes that arrive before the answer; watching an id again replaces it |
| `_native/fs/unwatch {watchID}` | stops a watch. A client that disconnects has all of its watches stopped |

The host watches with `HostCore.Configuration.fileWatching`: `FSEventsFileWatching` on a Mac
(`NativeHostMac`, set up like the Git package's `RepositoryWatcher`), otherwise `PollingFileWatching`,
which walks the folder every 2 s and compares (links recorded, never followed). A walk stops at
200,000 entries; then any change it sees is an overflow, and changes deeper than where it stopped go
unseen. A Linux host adds an inotify watcher behind the same `FileWatching`
protocol.

On the client, `RemoteFiles` (`NativeHostClient`) is both the reader and the feed: `read(_:range:)`,
`data(at:limit:)` (in 1 MiB ranges, starting again if the file changes between them), `info(at:)`
(nil when nothing is there), `entries(in:)`, and `changes(under:)`, an `AsyncStream` of
`RemoteFileChange` with absolute paths. The feed outlives dropped connections and host restarts: it
watches again on every new connection and then yields an overflow, since changes in between went
unseen; a watch the host refuses finishes the stream. The Git package's `HostRepositoryMonitor` makes
that feed a `RepositoryMonitor`, sorting the host's paths by the same rules as FSEvents' on this Mac
(paths compared as git spelled them, since only the host can resolve them). So a remote project's git
is `Git(environment: [:], runner: RemoteCommandRunner(client:), monitor: HostRepositoryMonitor { … })`;
diffs and Files Changed need nothing more, since they read through `Git.runner`.

**Errors.** The host's own errors use codes -33001 and below with `data: {"hostError": <name>}`;
`HostErrorCode(error)` names them (`agentUnavailable`, `agentNotInstalled`, `busy`, `unknownSession`…).
-32000 stays ACP's `auth_required`, and errors an agent returned pass through untouched. New codes are
appended to `HostErrorCode.code`'s order, so existing ones never move.

**Events.** A session is an ordered log of `HostEvent`s numbered by `seq`. Agents' `session/update`
payloads travel **verbatim** (`update`), so every client folds them with the same ACP `SessionState`
reducer; Native's own facts are typed events: `reset(loading)`, `loaded`, `prompt` (every message
delivered, shown or not, with its request id, attachments and preamble marker; agents don't echo live
prompts), `permissionRequested`/`permissionResolved`, `questionAsked`/`questionResolved`,
`turnEnded`, `turnFailed` (with the agent's JSON-RPC error, so `auth_required` and usage-limit data
survive), `notice` and `recovered`. `SessionMirror` folds a log into a transcript at each event's own
time, so a client attaching later times turns the same; the host keeps one per session too (that's
how it reads an agent's replay), folded only when it reads it. Clients get each event as a
`SessionMirror.Step`, its agent payload already decoded, from `NativeHostClient.addEventHandler`:
handlers run in order, and a response returns only after the events before it were handled. Attach
replays only what a client missed (same epoch, `afterSeq`) or the whole log from its `reset`, as
notifications before the response, like `session/load`. So a client never misses or doubles an
event, across reconnects and host restarts. Unknown event types and enum values decode as
`unsupported`/`unknown`, so an older client survives a newer host.

**Streaming cost.** The host keeps each session's log as encoded events. An agent's update is
parsed once (`JSONSerialization`, `AgentUpdate`), the host reads the few fields it needs from it, and
its JSON is spliced into the event as the agent sent it; live notifications and attach replays write
those bytes without encoding again, and a channel's writes go out together per burst. The host's
own mirror decodes the log only when the host reads it. Clients decode each event once, its agent
payload straight into a `SessionUpdate` (`SessionMirror.Step`), with `DecodedJSONValue`, because
`JSONValue`'s own `Decodable` conformance throws at every type it tries (about 28 µs a chunk).

`HostStreamingTests` measures a fake agent's stamped chunks decoded into `SessionUpdate`, straight
from the agent and through a host process, on a Mac shared with a dozen busy agents (load 20 to 50,
so the spread is wide):

| Stream | Direct to the agent | Through the host |
| --- | --- | --- |
| A chunk a millisecond (a fast model), latency p50 / p99 | 0.1 to 0.27 ms / 0.2 to 9 ms | 0.22 to 0.47 ms / 0.4 to 8 ms |
| 20,000 chunks as fast as the agent writes | 13,000 to 61,000 a second | 7,000 to 24,000 a second |
| CPU per chunk in that flood | client 31 to 40 µs | client 64 to 70 µs, host 57 to 66 µs |

So at the rates agents stream the host adds about a tenth to a quarter of a millisecond; only a
flood far beyond any agent shows the extra hop, and the remaining cost is per-message actor hops and
thread wake-ups rather than JSON.

**What the full UI needs on top** (designed; Phases 3 and 4), so the iPad runs the whole app against
a host:

| Area | Methods | Notes |
| --- | --- | --- |
| Usage and limits | `_native/usage/snapshot`, `_native/limits/changed` | the limits service and scheduled resumes move into the host |
| Host status | `_native/host/status`: memory, CPU and agent processes on top of what it has | for the status bar and the hosts list |
| Goals, workflows | `_native/goals/*`, `_native/workflows/*` | engines run in the host; clients mirror, as they do tasks (`_native/tasks/*`, done) |

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
| `sessions` | open sessions: host id, agent and agent session id, cwd, parent, origin, title, last activity, last stop reason, queue paused, MCP servers and `_meta` to hand over on reload, config values chosen, whether it was adopted from the agent's list |
| `turns` | the unfinished turn per session: request id, text, content blocks, attachments, preamble, kind (prompt or recovery), echo, start time, recovery attempts |
| `queue` | queued messages in order, with what each carries and a steering-in-flight flag |
| `requests` | prompt request ids and what they became (pruned after 7 days) |
| `approvals` | permission requests waiting on the user, as facts |
| `activity` | the journal: turns finished, failed or stopped, approvals and questions asked, recoveries, host starts with how the previous run ended; each with the agent and its session id |
| `notifications` | the notification backlog: the newest 200, each as JSON with its id and state (`active`, `acknowledged`, `resolved`) in columns |
| `tasks` | the tasks sessions handed each other through Native's tools: the engine's record as JSON, by task id |
| `titles` | per session: the user's title, the generated one, and while one is still wanted, the project name, first message and progress (`generating`, `waitingForClient`, `failed`); goes with its session |

Phase 3 adds `goals`, `workflow_runs`, `resumes` (scheduled limit resumes) and `unread`, all owned by
their engines inside the host.

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
| Host restarted for an update (Restart Host Now) | a restart mark in `meta`, written just before exiting | resumes every unfinished turn like a crash | "Native's background host restarted at 2:14 PM to update. …" |
| Host killed or crashed | unfinished turns at startup, same boot | launchd restarts it; it resumes every unfinished turn, then drains queues | "Native's background host stopped unexpectedly at 2:14 PM. …" |
| Mac restarted or logged out | boot time differs from the last run's | resumes at login | "Your Mac restarted at 2:14 PM while Codex was working. …" |
| The prompt never reached the agent | not in the replay | resends with the same request id | "Your message hadn't reached Codex yet, so Native sent it again." |
| A steer was in flight | queue item flagged steering | dropped if the replay has it, otherwise it goes out as the next message | the message shows once, where it landed |
| Permission request pending | it dies with the agent process | withdrawn; the agent asks again after resuming | the approval card disappears, then reappears from the agent |
| User cancels during recovery | `session/cancel` while recovering | recovery stops; turn ends as cancelled; queue pauses | "Stopped." |
| User restarts the agent mid-turn | `_native/agents/restart` | like an agent crash, with its own cause | "You restarted Codex at 2:14 PM. Native asked it to pick up where it left off." |
| A session the agent never saved can't load | `session/load` fails for a session started here that never finished a turn | starts a fresh agent session under the same host id; recovery then resends the message | the message, answered (nothing was lost: the agent had nothing) |
| The prompt fails for a passing reason (network, overloaded provider) | the agent's error reads like an outage, and the turn got nowhere | puts the message back at the queue's front, unshown, and sends it again after 5, 20, then 60 s (`retryAt`); Stop cancels the retry | "Codex couldn't be reached (…). Native kept your message and will try again in 5 seconds. Use Stop to cancel." |
| The agent never confirms a stop | no answer 10 s after `session/cancel`, or Stop again after a second | ends the turn as cancelled on the host's side; a late answer is ignored | "Codex didn't confirm it stopped, so Native stopped waiting. It may still be finishing its last step." |
| Client disconnects mid-turn | socket closes | nothing: the turn runs on; the client re-attaches from its last event | the finished turn, as if it never left |
| Client quits while an approval or question waits | socket closes | nothing: the agent keeps waiting, and the request stays in the session's log | the next client to attach (the app relaunched, an iPad) shows it and can answer it |

The interruption time comes from the host's heartbeat (written every 30 s), so "at 2:14" is within
half a minute; for agent crashes it's exact.

**While you were away.** The activity journal records finished and failed turns, approvals asked,
and every recovery with its cause and action; each entry carries the agent and its session id, so
it leads to its task even after the host closed the session. The app keeps, per host id, the last
entry it showed (`NativeHostSeenActivity`). On its first connection of a run it reads everything
after that (a host's very first connection only sets the baseline) and `AwaySummary`
(`NativeHostClient`, so every client tells the same story) folds it into one item per task and a
headline: "1 task finished, 1 needs your approval, and 1 failed. Claude Code stopped once and Native
resumed it." Approvals already answered elsewhere, the user's own stops and the host's bookkeeping
are left out; one host crash that interrupted several tasks counts once. `HostAwayCard` shows it
above the detail column: tasks that need the user first, each with its status, title (the
sidebar's), what happened and when, opening its task on click; four rows, then Show All. Opening a
task takes it off the card, and the card goes when it's empty or dismissed. Entries that arrive
while the app is connected are news already and only move the baseline. Recoveries also show inline
in the transcript, where they happened. With host notifications on (`NativeHostNotifications`), the
card is folded from the host's notifications instead, so what was seen on another device is left out
("Notifications", "Coming back").

**Approvals while away.** The host posts a notification for each approval (see "Notifications"),
whether or not a client is there; every client shows it, Allow and Reject on it are host requests,
and answering it anywhere takes it down everywhere. The menu bar extra (Phase 3) lists sessions
needing approval. Approvals stay in `approvals` so a restarted host can tell the user one was
pending even though the agent will ask again.

## Notifications

Agents run on a host whether or not anyone is looking: a laptop that kicked off a job and closed its
lid, a Mac mini in a closet. So the host decides what's worth telling the user, and every client
(the Mac app, for its own host and every paired one; the phone, by push, later) shows the same
notifications and clears them together. The protocol is `NativeHostProtocol/HostNotifications.swift`,
the host's side `HostCore+Notifications.swift`, the Mac's `native/Notifications/`.

**What's posted.** `HostCore` turns its own session events into notifications as they're logged,
with no client needed, and keeps them in the store (`notifications`, the newest 200; ids keep
counting across restarts and dropped rows, so `(HostID, id)` is stable):

| Kind | From | Carries | Actions |
| --- | --- | --- | --- |
| `permission` | a tool call waiting for approval (a subagent's opens its parent's task) | tool title, `toolCallID`, the agent's allow and reject option ids | `allow`, `reject`, when the agent offers them |
| `question` | a form question (`elicitation/create`) | the question, its `questionID`, its one free-text field | `reply`, when one line of text answers it |
| `turnFinished` | a top-level turn ending `end_turn` | duration, files changed | |
| `turnFailed` | a turn that failed and isn't being retried | why | |
| `limitReached` | a turn that failed on the provider's usage limit (`UsageLimitHit`) | the provider's message, the reset time | |
| `recovered` | an interrupted turn Native did something about | the `RecoveryNote` | |

Tasks Native's tools started (`origin: task`) report through their run and post nothing, as in the
app. Every notification names its agent, the agent's session id and the task's title, and belongs to
a `group`: one per task, and one per provider for limits. Clients show the newest of each group
(an APNs collapse id on the phone).

**Clearing.** A notification is `active` until it stops being news, and then every client hears
`cleared` and takes it down:

- `resolved`: the approval or question was answered (on any client, or through `act`) or withdrawn
  (the turn was stopped, the agent went away, the host restarted: agents ask again once their
  sessions resume, which posts anew).
- `acknowledged`: a client says the user saw it (`acknowledge`): they opened it, acted on it,
  dismissed it, or opened its task; acknowledging one also clears older ones of its group. Writing
  to a task from any client acknowledges what it said before (not its open approvals).

`act` answers through the same code as `respond_permission` and `respond_question`, so the first
answer wins wherever it came from, and a client that follows the session can answer with those
directly (the notification carries the option ids).

**On the Mac** (`HostNotificationFeed`, one for the app, behind `NativeHostNotifications`). It
follows this Mac's own host from launch and every paired host through `RemoteHosts`; notifications
from a paired host say which ("Codex on Mac mini"). Live notifications show as Native's always have
(the words of `NativeNotification`, Settings › Notifications' choices: needs you, long work and its
threshold, usage limits), never about the task on screen: one that arrives while the user looks at
its task is acknowledged instead. Limits for tasks this Mac has open stay with its own limits engine,
which offers Resume at Reset. A click opens the task; Allow, Reject and Reply go to the host with
`act`, and whatever a notification can't do opens the task. Responses that arrive before their
host connects (a click that launched Native) wait for it.

With the switch on, the app's own path stays quiet about sessions a followed host runs, so nothing
shows twice; sessions that run in the app (no host), workflows, goals and limits notify as before.

**Coming back.** The Mac remembers, per host, the newest notification it heard of
(`NativeHostSeenNotifications`). After connecting it lists what came after: a host's first connection
only sets that mark; a single fresh notification after a dropped connection shows as if live;
anything more is summed up, never replayed one by one. A host's first connection in a run (this
Mac's at launch, a paired host's when it first answers) sets its "While you were away"
(`AwaySummary(notifications:)`, the same folding as the journal's): this Mac's host's on
`DurableHost.away`, a paired host's on its `RemoteHost.away`, shown with its name. A paired host, or
any host while Native is in the background, also gets one notification with the summary's headline
("While you were away from Mac mini").
Only what's still `active` counts: an approval answered on the phone, or a finished task seen there,
isn't news on the Mac. On every connection the Mac also takes down what it shows (from this run or
an earlier one, read back from the notification center) that was cleared while it wasn't listening.

What durability doesn't fix: a context window that's full, a provider outage, or side effects a tool
call made outside the project (a deploy, an email). Those are surfaced, not hidden; the interruption
message asks the agent to check before acting again.

## Titles

A task is named after its first message the moment it starts. That has to happen where the task
runs: a job started from a laptop that then closed its lid, on a Mac mini, still gets its name, and
the user's renames hold on every client. So the host writes titles and keeps them. The engine is
`Packages/SessionTitling` (the rules, `SessionTitleState`, and `OnDeviceTitleGenerator`, the
on-device model the app and the host share), the host's side `HostCore+Titles.swift` and
`HostStore+Titles.swift`, the protocol `NativeHostProtocol/HostTitles.swift`, the app's
`native/Plugins/SessionTitles+Host.swift`. It's behind `HostTitles` (the user default
`NativeHostTitles`, read at launch; off by default until it's verified in the running app, and
`-NativeHostTitles YES` turns it on); off, the app titles tasks as it did before and tells the host
not to (`provider: off`).

- **Who writes them.** At connect, after every reconnect, and whenever the titles plugin or the
  user's title instructions change, the app sends `_native/titles/configure {provider,
  instructions}`; the host keeps it in `meta`, so it holds with no client attached. `on-device`: the
  host runs Apple's on-device model itself. `client`: a titler that runs only in apps
  (docs/plugins.md, "Titles with the app closed"). `off`: titles are off in Settings ▸ Extensions.
  `instructions` are the user's title instructions (global, per project, the organization's), which
  the host applies for each task's folder. Only the owner, or a device allowed to manage the host,
  may change it.
- **When.** As a task's first message starts its turn (not a session adopted from the agent's list,
  not one with earlier messages), the host commits what the title is written from (project name,
  the message up to 2,000 characters, `progress: generating`) and then writes it. Committed first,
  so a host that stops mid-title writes it at its next start.
- **No model on the host** (Apple Intelligence off on a Mac mini, a Linux host), or provider
  `client`: the summary's `titles.request` asks clients, and the first one with a titler writes it
  and sends it with `_native/session/set_title {source: generated}`. Meanwhile, and when the model
  failed, `titles.fallback` names the task from its first message (its first line, cut after eight
  words), shown after the agent's own title, so a task is never nameless while there's anything to
  name it by.
- **The user's title wins.** A rename, from any client, and its undo (the previous title, or none)
  go to the host with `_native/session/set_title {source: user}`; every client hears the change. The
  first generated title stays: neither a client's nor the host's late one replaces it.
- **Clients** read `HostSessionSummary.titles {user, generated, fallback, request}` from
  `_native/session/changed` and show the user's, the generated one, the agent's (`summary.title`),
  then the fallback. The app copies them into its own title store, so tasks the host later closes
  keep them, and gives the host titles it never had (renamed or titled before titles moved to the
  host, or before the host reopened the task). A rename it couldn't send goes when the host is back.
- **Workspaces follow.** The Git feature renames a task's provisional branch after its first title
  (`TaskWorkspaceProvider.taskDidGetTitle`), in the app, whenever a title lands from a host: live,
  or at the next launch for a task titled while the app was closed. For a paired host's task the
  provider runs git there (`RemoteHostsWiring`), so the same path names remote workspaces.

## Native's tools in the host

Native gives every agent session its own tools, as an MCP server named `native`: `list_agents`,
`start_task`, `list_tasks`, `wait_for_task`, `get_task`, `send_message` and `cancel_task` to hand
work to other agents, and `list_skills` and `get_skill`. When the host serves them, it also runs the
tasks agents hand each other, so delegated work goes on while the laptop is closed, and a session on
a droid gets them from its own host. It's behind `HostTasksSetting` (the user default
`NativeHostTasks`, read at launch and sent to the host at every connection); off, or with an older
host, the app serves the tools itself ("Native's MCP server across launches").

- **One engine, two runtimes.** `Packages/Orchestration` (`NativeOrchestration`) is the engine: the
  tools' definitions, `TaskOrchestrator` (who reaches whom, the reports models read, reopening a
  task after a restart), `TaskPromptFrame` and the task record. It runs over a `TaskRuntime`:
  `HostTasks` in the host (`HostTasks.swift`, `HostCore+Tasks.swift`, `HostStore+Tasks.swift`), or
  `AppTaskRuntime` when the app serves the tools. Both read a session as a task the same way
  (`TaskSnapshot(phase:…)`), so a task reports the same wherever it runs.
- **Where it listens.** On the host machine's loopback, so on a droid it's the droid's own address
  for the droid's agents. The port and the token secret live in `<host dir>/MCP/`, kept and moved
  as the app's were (the remembered port, five seconds' patience, a move retires the secret). A
  token is `MCPTokenSigner`'s HMAC-SHA256 over the channel and the session's `HostSessionID`, keyed
  by the host's secret: a bare session id, which every client and the machine's processes may know,
  or a MAC from any other secret gets 404 (`HostTasksTests`).
- **Every load gets this run's address.** The host adds its `native` entry to the servers a client
  handed it (in place of any client's `native` entry) at `session/new` and at every
  `session/load`, once its server listens. So a URL is never stale: recovery after a restart reaches
  the tools, and no session is left behind on an old port, since agents die with their host.
- **Tasks are host sessions.** `start_task` starts a session of the task's agent in the parent's
  folder, with origin `task` and the caller as its parent, and records it in `tasks` (the id agents
  use, such as `task-ab12cd`; the task and its parent named by agent and agent session id, which
  outlast the host's ids; its title and folder). The parent's words go into the task's log as a
  `session_message` update, the task is prompted with them framed by `TaskPromptFrame`, and the
  parent's log gets a card: a `subagent_update` whose `_meta["native.task"]` names the task and its
  host session. The card follows the task (running, needs approval, how its turn ended), and after
  every reload of the parent, whose log starts over, the host puts its tasks' cards back, opening
  (without loading) any task session it no longer has. A task whose agent never saved its first
  session carries on in a fresh one, and its record follows.
- **What a new task session is handed.** MCP servers and `_meta` come from clients' plugins, which
  the host doesn't run. It gives a task those a client last gave a session of the same agent in the
  same folder; else the parent's, when it runs on the same agent; else the parent's servers (they're
  the project's) without `_meta` (that's its agent's).
- **Waiting.** `wait_for_task` waits on the session's own changes, no polling, up to the caller's
  timeout; an agent that gives up on the call (it hangs up) ends the wait.
- **With no client attached** nothing changes: tasks start, run, take messages, stop and are waited
  on, and recover like any host session. `HostTasksTests` runs a task and its parent to the end with
  no client, and SIGKILLs the host while the parent waits on its task: both resume, the port is the
  same, and the card is back.
- **The app** sends `_native/tasks/configure {servesTools, disabledSkills}` at every connection.
  When the host serves, the app stops its own server and hands no `native` entry; it mirrors the
  tasks (`_native/tasks/list`, then `_native/tasks/changed`), which names a replayed task prompt's
  sender and keeps task sessions out of the sidebar; and it opens each card's task as the task
  session it is (`AppModel.claimHostTask`), so the card, the task's transcript and talking to it are
  as before. Only a client on the host's machine may configure it.
- **What needs the app.** `setup_status` reports the Mac app's own state (its build, Settings ▸
  Agents, paired devices, updates), and `run_script` runs in the app's script runtime with the app's
  MCP library bound. The app offers both in `configure` (`appTools`, kept in `meta`), and the host
  lists them for its sessions and passes each call to that app (`_native/tasks/app_tool_call`,
  answered with `_native/tasks/app_tool_result`; how a tool lists for a session too, with a second's
  patience). The app's `run_script` binds the host's own task tools (`_native/tasks/call_tool`), so
  a script sees the host's tasks. With the app closed, they stay listed (agents read a session's
  tools once) and a call says why it can't run and that the other tools work without the app
  ("…runs in Native's app on <machine>, which isn't open right now…"). Native's skills come from
  the app the helper runs in (`MacHost.bundledSkills`): a standalone host has none and offers no
  skill tools. The skills switched off in Settings (everywhere, or per project) travel in
  `configure`.
- **Other platforms.** The server needs Network and CryptoKit, so elsewhere the host serves no tools
  (`HostTasks.canServe`) and says so once in its log; the task logic is portable.
- **Earlier tasks.** Tasks the app started before the host served the tools stay in the app's
  records (`orchestrationTasks`); the host doesn't know them, so their parents don't list them.

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
generated launchd plist, `SMAppService` registration (session-only `LaunchdSessionJob` for Debug
builds) and `scripts/dev/clean-host-channels.sh`. `native/Host/`: registration, connection and the
Window › Durable Sessions preview, opt-in per channel. Nothing else in the app changes.

**Phase 2: the app becomes a client** (models agent, against `NativeHostClient`). The public API of
`AppModel` and `SessionModel` stays as it is; their insides change:

1. `AgentRuntime` becomes host-backed: status, capabilities and auth methods come from the host
   (`_native/agents/list`); `start`/`restart`/`signIn` become host requests. The app stops spawning
   agents; `AgentProcess` is used only inside the host. Done: with `HostSessions` on (the
   `NativeHostSessions` default), `AppModel.connectHost(client:)` makes every `AgentRuntime` take its
   status from `_native/agents/changed` (`AgentRuntime.apply`, decoding the agent's `initialize`
   result) and start, stop, restart and sign in through the host (`AgentRuntime+Host.swift`). Idle
   parking asks `_native/agents/stop`, which the host refuses while the agent works. Requests outside
   turns go through `AgentConnection`: `ACPConnection` for agents in the app, `HostAgentConnection`
   (list and delete sessions) for agents in the host, so listing and archiving code didn't change.
2. `SessionModel` keeps `state`, `phase`, `queuedPrompts`, `needsApproval` and every method. It holds
   a `SessionMirror` fed by the client's events and a `HostSessionSummary`; `send`/`submit` become
   `session/prompt` with a fresh request id (retried with the same id after a reconnect), `cancel`,
   `choose`, `setConfigOption` and the queue edits become their host methods. `clientID` is the
   `HostSessionID`, now stable across restarts. The host side is done and does what
   `SessionModel+Turns`, `+Stop`, `+Questions` and `+HiddenCommands` and `TurnRetryPolicy` do today
   (prompt content and preambles, stopping, questions, hidden commands, retries, queue moves and
   undo), so they work with no client attached; `SessionMirror` reproduces `SessionState` from the
   events, timings included. Client side done (`SessionModel+Host.swift`): the transcript is the
   mirror's state, events that happened before the model followed the session rebuild it without
   reaching plugins again, and each action dispatches to its host request. Messages sent while a
   session loads and gets its chosen settings back (`ConfigChoices`), or while a workspace hold lasts,
   wait in the model and go out in order afterwards. Native's own approval cards (script calls) stay
   local. A session the host gives a fresh agent session (it was never saved) carries on under its
   new key with its title, settings and place.
3. `SessionStore` routes `NativeHostClient.events` instead of `AgentEvent`s; `SessionLauncher`
   calls `session/new` and `_native/session/open`. `SessionCatalog` keeps listing history through
   the host (`_native/agents/list_sessions`, which wraps the agent's `session/list`). Done: sessions
   are opened with `attach` so their replay streams into the model as it loads, one open per session
   at a time, under the session's existing `HostSessionID` when the host already has it. On connect
   and reconnect the app syncs agents and opens the user's sessions the host is working on, so the
   sidebar shows work that went on while it was closed.
4. Plugins still supply agents (sent with `_native/agents/sync`) and per-session MCP servers (sent as
   JSON with `session/new`, with their `_meta`), so the plugin API is unchanged. Done: each spec
   carries the plugins' launch-policy environment, and a changed policy restarts the agent through
   the host.
5. `LoginShell` moves to `UserShell` (already in the package); `native/Models/LoginShell.swift` goes.
   Done.
6. ⌘Q quits only the client; "Quit Native and Stop Agents" and the attached-host fallback land.
   Done. The attached host is `NativeHostClient.AttachedHost`, which runs the helper with
   `--exit-with-parent` (`NativeHostMac.ParentWatch`: when the app goes, `kill -9` included, or the
   host gets SIGTERM, SIGINT or SIGHUP, it ends running turns as stopped by the user, stops its
   agents, writes the clean-shutdown mark and exits 0, so the next host never reads quitting as a
   crash).
7. The app shows connection states and the "while you were away" summary. Done.
   Native's MCP server keeps its port and each session's token across launches, so host sessions
   keep Native's tools when the app restarts ("Transport and security"). Done.
8. Background agents are on by default (`HostSessions.defaultValue`), now that the host-backed path
   passes its end-to-end checks; the Window › Durable Sessions preview is gone. Done
   (docs/decisions.md, 2026-10-20).

**Phase 3: engines move into the host**, one PR each, each keeping its client-side API: the
orchestration MCP server (done: "Native's tools in the host", behind the `NativeHostTasks` default;
`setup_status` and `run_script` are answered by the app), titles (done: "Titles",
behind the `NativeHostTitles` default), notifications with
actions (done: "Notifications", behind the `NativeHostNotifications` default), limit resumes, goals and workflows, keep-awake (done: "Sleep"), the menu bar extra, unread state. The
plugin registry's runtime side follows (the plugin API moves into a package both sides import).
Engines come to the host as packages, never as app-target files: goals, workflows and automations
link `Packages/Automation` (Foundation-only, Codable, pure state plus a `due(at:)` planner), and the
host implements its `AutomationHost` (start a workflow run, prepare a worktree, poll GitHub), with
runs persisted in the host's store.

**Phase 4: other machines.** Exec, files and the change feed in the protocol; the SSH transport and
remote provisioning; the paired network transport and the iPad app. Commands and projects are done
("Commands and projects"), with the `runCommands` grant checked by the gateway and the host.

## Risks

| Risk | Mitigation |
| --- | --- |
| Agents launched by launchd see a bare environment | the host reads the login-shell environment (`UserShell.LoginShell`), as the app does today |
| Privacy prompts (Desktop, Documents) attribute to "Native Host" | the helper is named and signed as Native; `AssociatedBundleIdentifiers` ties it to the app; documented in onboarding |
| User disables background activity | detected via `SMAppService.status`; attached-host fallback, with an explanation |
| A host bug kills every session at once | crashes are recovered like any interruption; recovery is capped per turn; the tests kill the host on purpose |
| Host and agent die together, so turns are interrupted rather than continuing | accepted: the recovery message is cheap and honest. A per-agent stdio relay that outlives the host could make host crashes invisible later |
| An agent's launcher (`npx`) dies but the adapter it started lives on, still holding the pipes | the host notes every process group in the agent's tree and ends them all when the launcher exits, the agent stops or crashes, or the host stops its agents (`AgentProcessGroups`); the session then recovers like after a crash. Agents launch without npx where npx has the exact version installed |
| Recovery prompts spend tokens | only turns that were actually running are resumed, at most three times |
| An agent stores the prompt transformed, or adds markers after it, fooling the replay check | the check accepts containment within the last three user messages; the worst case is a harmless "you were interrupted" for a prompt it never saw |
| The in-memory event log grows with long sessions | cleared on every reload; a cap that reloads from the agent instead of keeping everything can come later |
| Protocol drift between app and host versions | version handshake, unknown-tolerant enums and events, restart-when-idle updates |
