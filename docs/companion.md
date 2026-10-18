# Companion app plan

The iPhone layout of Native, in the spirit of the reference app's and the reference app's companions: check on tasks away
from the Mac, approve permission requests, steer or queue follow-ups, start a task, and get notified
when something finishes or needs you. The iPad runs the full app instead (see "Clients and hosts" in
`docs/architecture.md`); both are clients of a host, paired and connected the same way. The host
keeps agents, worktrees, credentials and plugins.

**Status (2026-10-18):** pairing, the encrypted transport and the host's gateway are built
(`Packages/NativeLink`); the Mac pairs devices in Settings › Paired Devices (`native/Companion/`);
the iPhone app is `Companion/NativeCompanion.xcodeproj`. Push, Live Activities and real-device
installs wait on an Apple developer team.

## Pairing and transport (built)

- **Identity.** The host has a static Curve25519 key (`<host dir>/Link/identity.key`, 0600, in the
  host's 0700 directory: the keychain would prompt for every development build's new signature).
  The phone makes a **new key for every host it pairs with**, kept in its keychain with that host's
  pairing (`KeychainPairedHostStore`, one item per host, this device only), so two hosts can never
  tell they share a phone.
- **The QR code** is a `nativecompanion://pair#…` link (the iPhone's Camera opens the app with it):
  the host's `HostID`, its public key, a 32-byte one-time secret, its name, the expiry (5 minutes)
  and its addresses (LAN and Tailscale IPs, the Bonjour name, loopback on development hosts; relay
  entries are reserved). Under it the Mac shows a six-character code for typing instead.
- **The handshake** is Noise (`Noise_XX_25519_ChaChaPoly_SHA256`) on CryptoKit, checked against the
  cacophony test vectors. Pairing uses `XXpsk3` with the secret (or the typed code) as the
  pre-shared key, so only a device that read the Mac's screen can finish it. With the QR code the
  phone checks the host's key against the one in the code before it reveals its own; with the
  typed code it learns the key in the handshake, and both screens show a six-digit verification
  code from the handshake hash that the Mac's user checks before trusting the device (a machine in
  the middle would make them differ). Every later connection is plain `XX`: both sides prove their
  static keys and check them against the pinned ones. TLS with pinned certificates was the
  alternative; see `docs/decisions.md` ("Companion transport: Noise over TCP").
- **Single use, short lived, three tries.** A window's secret and code die when a device proves
  them (whatever the Mac's user then decides), when the window expires, or after three wrong
  codes. Nobody confirming within two minutes declines.
- **Framing.** TCP (Network.framework, keepalive on) carrying frames of a 2-byte length, a kind
  byte and a body: the device's hello (link version and mode, also the Noise prologue), Noise
  messages, and, only before keys exist, a one-byte refusal (no window, wrong code, too many
  tries, busy). After the handshake the host's first encrypted word is a welcome (`ok`, `paired`,
  `revoked`, `unknownDevice`, …), then the host protocol's NDJSON runs over the channel unchanged.
- **Grants.** What a device may do beyond following and driving tasks is chosen on the Mac when it
  confirms the pairing, and changeable later: install updates (`manageHost`, offered on for QR
  pairing, off for typed codes) and turn plugins on and off (`managePlugins`, off). The gateway
  enforces a method allowlist per device (`LinkMethodPolicy`) and hands the grants to the host as
  its `ClientGrants`; `_native/host/shutdown`, `_native/agents/sync` and `update/report` never
  cross a link, and anything not listed (future exec and file access) is refused until a grant
  covers it. The device's `initialize` is renamed to the name the Mac confirmed, so anything the
  host records as "from <device>" is true.
- **Off by default.** With nothing paired and no window open, nothing listens on the network.
  Opening the Pair iPhone sheet turns the gateway on (`devices.json` remembers it and the port);
  Settings › Paired Devices can switch it off without forgetting devices.
- **Discovery.** The gateway advertises `_native-link._tcp` over Bonjour with its key fingerprint
  and `HostID` in the TXT record; the phone tries the Bonjour service first, then the saved
  addresses. A second Native on the same Mac takes another port and Bonjour renames it.
- **Revocation.** Revoking a device closes its live connections and refuses its key at the next
  handshake with an authenticated `revoked`, so the phone says "removed on the Mac" (with Pair
  Again, or Try Again after an undo) instead of retrying forever. Revoked devices stay as
  tombstones so revoking can be undone, and the gateway keeps listening for them until Forget
  Revoked, so a removed phone is told rather than refused at the door. TCP connections close only
  after their last message is sent, so refusals and "revoked" always arrive.
- **Re-pairing.** The phone sends a per-host installation tag (a hash of an installation secret and
  the host's key), so pairing the same app again replaces its old entry on the Mac instead of
  adding a duplicate, without giving two hosts anything in common. On the phone, pairing a host
  again keeps what it called the host (name, color, icon).

### Host integration

The gateway lives in the host process (so it works with the Mac app closed) and is plugged in by
`NativeHostHelper/main.swift`: `LinkGateway(configuration:accept:)` with the host's `HostID`, then
`start(verifyPeer:)`. Admitted streams go to `HostCore.accept(_:grants:)`. The Mac app drives it over
`<host dir>/Link/link.sock` (`LinkControlClient`: status, open/close/decide pairing, revoke, restore,
rename, grants, on/off), with the same uid and code-signature checks as the host socket.

## Many hosts

The phone pairs with host instances, keyed by `HostID`: a Mac, a run box, or two Natives on one Mac
are separate hosts. Each has its own key, connection, cached data, plugins list, update state,
connection log, name, color and symbol, and notification choices (`HostPreferences`), and
unpairing one never touches another. The home screen groups everything by host (filterable to
one), a task always belongs to one host and its actions go there, and notifications thread per
host. Names default to the machine's own name; the person names hosts however they like. Add Host
lives in Settings, and a pairing link opens it from anywhere.

## The iPhone app

`Companion/NativeCompanion.xcodeproj`, its own project so it can never break the Mac scheme. It
compiles `native/DesignSystem` (a synchronized folder) and the Mac's transcript pieces by reference
(`MarkdownView`, `ToolPresentation`, `ToolPhase`, `FileDiff+DiffView`, `TranscriptStyle`,
`TranscriptMetrics`, `TranscriptFixtures`, plus `CelebrationDates`), so tool rows and approvals use
the Mac's exact words, and links ACP, NativeHostClient, NativeLink, NativePolicy, CodeThemes and
AppAppearance. Screens follow `research/companion-app.md`: welcome;
Add Host (scan with VisionKit's DataScanner, pick a Mac Bonjour found and type its code, or paste
the link); pairing progress with the verification code and a pairing log; Tasks grouped by host
(needs you with inline approvals, working, recent); a task's transcript (the shared `SessionState`
via `SessionMirror`), the docked approval card, queue/steer composer and queued messages; New Task;
a host's page (connection and log, Native version and updates, plugins, name/color/symbol,
notifications, app icon while connected, unpair); Settings (hosts, appearance, app icon and
celebrations).

- **Unsent messages** go back into the draft marked "Not sent"; nothing is cleared until the host
  accepts it. **Interrupted turns** show the host's recovery notice in the transcript, and a lost
  connection says the agent keeps working on the Mac. **Answering on one device clears it on the
  other**: the host resolves the request for every client.
- **Updates** follow `docs/releasing.md` ("Remote updates"): "Update available · 1.4.0" on the
  host row, notes and Update Now on its page, a choice between Install When Idle and Install Now
  (interrupting N tasks) when tasks run, progress through the restart and reconnection, failures
  and rollbacks in words. Without the grant it says why instead of hiding the button. A local
  notification announces a new update while the app runs.
- **Plugins** are listed from `_native/plugins/list`, with switches only when the pairing granted
  `managePlugins`. Appearance-only plugins installed on the phone are a second source for the same
  list later.
- **Approvals** are the one approval card, weighted by what the agent offers: its "allow once" is
  the filled primary button, other allows are outlined, rejections are plain text last. Option names
  wrap (up to three lines) with their `code` spans in the mono face. A shell command shows as typed
  under a dimmed `$`: `ToolCallState.shellCommand` (`Packages/ACP`) reads it however the agent sent
  it, including codex-acp 2.2.2's permission requests, which carry it JSON-encoded a second time
  ("printf 'ship\\n' > todo.txt" in quotes) and retitle the call "Run command", and argv arrays
  (`bash -lc <script>` is the script). The Mac's `ToolPresentation` uses the same property, so its
  Codex rows show the command, not "Run command".
- **Which host.** A host's color and symbol (its page, "On This Phone") are a quiet, always-on
  accent: the home screen's header chip shows the active host (its mark and name, or "All Hosts"
  with every host's marks) and switches it, along with Needs You Only; that host's color tints the
  home list and toolbar buttons; a task's header carries its host's mark, and the task, its
  sheets and the host's page tint with its color. Filled actions (Yes, proceed, New Task) keep the
  app's accent, and a host left on Original has no color of its own, so with one uncolored host
  nothing changes. "App Icon While Connected" on a host's page switches the app icon when that
  host becomes the active one (picked in the chip, or the only host).

- **Later, with a developer team:** APNs push (the categories in the research doc, threaded per
  host) and one Live Activity per host; `CompanionNotifications` is the seam. The full
  `TranscriptView` stays Mac-only until it no longer needs `SessionModel`/`AppModel`; the phone's
  rows are its own, built on the same `SessionState` items and `ToolPresentation`.
- **Organization policy.** `policy.companion.enabled` off: the Mac page explains it and locks its
  rows, the gateway stops listening, opens no window and answers paired devices with an
  authenticated `disabledByPolicy` (pairings kept), and the phone's Add Host says pairing is off.
  The host reads the policy from the app's managed domain (`LinkGateway.setAllowedByPolicy`).

### App icons and celebrations

Settings › App Icon picks the icon (Original or a theme, which also sets the accent, as on the
Mac), opens Celebrations, and has the one switch that keeps the icon fixed. The icon showing is, in
order: a celebration on its dates, then the active host's icon, then the picked one; Keep Icon
Fixed leaves only the picked one. Celebrations use the Mac's catalogue and overlap policy
(`Packages/AppAppearance`): every one is off until turned on, then shows on its dates (Halloween's
season, Día de Muertos and Australia Day in the style picked), on the phone's own choices. The phone
has no Home page, so only the icon counts. iOS changes the icon only while the app is active and
shows an alert every time, so a change that falls due on its own (a celebration starting or ending)
waits until the app next becomes active and is tried once (`AppIconController`); a change the
person makes (a theme, a host's icon, switching hosts, a celebration) applies at once.

iOS can't download alternate icons, so they're bundled, built from the icon work's documents by
`scripts/companion/app-icons.sh`, which the companion target runs as its first build phase into
the gitignored `Companion/AppIcons/` (nothing there is committed, and nothing is drawn or edited):

- The five themes stay layered `.icon` documents (Regular `stable.icon` from
  `design/app-icon/channel-themes/<theme>`), so iOS draws their light, dark, tinted and clear looks.
- Every celebration edition and style (45, Halloween included; the release script's PENDING and
  EXCLUDED editions are left out) is flat: Icon Composer's `ictool` renders its Regular `stable.icon`
  light and dark at the iPhone icon sizes into an app icon set. Tinted is iOS's automatic tint of
  the light icon.
- Every icon, the primary included, gets a 48 pt light and dark preview for the pickers, since iOS
  can't load app icons as images (`UIImage(named:)` on one crashes).

Why celebrations are flat: Xcode bakes 1024 px light, dark and tinted renders of every layered
document for phone and pad, about 6 MB each. Measured with Xcode 27.1 (Release, iOS 27): all 50
icons layered would add 319 MB to the app (about 168 MB on an iPhone after App Store thinning);
as built, the themes add 23 MB, the flat celebrations 23 MB and the previews 3 MB: about 50 MB in
the app and about 18 MB on an iPhone. A clean checkout builds without manual steps, but needs Xcode 26 or later
(for `ictool`) and, once `design/**/*.png` moves to Git LFS, `git lfs pull`: the script fails with
that instruction rather than building blank icons.

### Verifying

`(cd Packages/NativeLink && swift test)` covers the Noise vectors, a full pairing over a socket
pair, a used or expired secret, wrong codes, a host with the wrong key, an unpaired key, revocation
(live connection cut, then refused, then restored) and a real TCP pairing through the control
socket, plus a revoked device being told so over TCP. End to end (2026-10-18): two isolated
instances (`scripts/dev/run-isolated.sh host-a` and `host-b`, Durable Sessions on, different
projects), each paired from the simulator with `CompanionEndToEndTests.testPairWithInvite` (the
invite read off the Mac's QR code, Pair clicked on the Mac through AX), then
`testSendPromptAndApprove`: list the host's tasks, open the Codex durable session, pick
`gpt-6.1-sol` and Read-only from the phone, send a prompt, and allow the permission request.
`testScreens` walks the screens in light or dark. Codex's models are labelled by name in its picker
(`COMPANION_MODEL="6.1 Sol"`).

Icons, celebrations and hosts (2026-10-18): `testAppIconAndCelebrations` walks Settings › App Icon
and Celebrations, turns on `COMPANION_CELEBRATION` (Halloween, in its season), accepts iOS's alert
and shows the home screen; `testHostChip` gives a host a color and an icon on its page, picks it in
the chip (the icon switches, with the alert) and opens its task; `testAllHosts` goes back to All
Hosts. `COMPANION_LEAVE_PENDING=1` makes `testSendPromptAndApprove` stop at the approval card, so
`testTaskScreen` can show it in the other appearance. Real Codex wire data for the card is in
`Packages/ACP/Tests/ACPTests/ShellCommandTests.swift`.

## Architecture

- **The phone is an ACP client of the Mac.** Native already turns many agents into one coherent
  set of sessions. It re-exposes them through a gateway that speaks ACP (session/list,
  session/load replay, session/prompt, session/cancel, session/update, permission requests,
  steering), with Native's extras (task status, goals, workflows, limits, usage) under `_meta` or
  `_native/*` methods. The phone app reuses `Packages/ACP` unchanged: the same `SessionState`
  reducer, so transcripts mean exactly the same thing on both devices.
- **Shared UI.** Transcript views (`MarkdownView`, `ToolCallView`, `DiffView`, `MessageView`,
  subagent cards) are plain SwiftUI and should stay free of AppKit so an iOS target can compile
  them. AppKit-only code (window chrome, `NSWorkspace`, process sampling) stays out of those files.
- **The gateway is the durable host.** Native's background host (`docs/durability.md`) owns every
  agent and session, so the phone talks to the same process the Mac app does, and it keeps working
  while the Mac app is closed.
- **Pairing is a QR code.** The Mac shows a QR code (Settings, and the first-run companion prompt);
  scanning it with the phone's camera pairs the device in one step. The code carries the host's
  public identity key, a one-time pairing secret that expires in a few minutes, and how to reach
  the host (local addresses, and the relay or tailnet address when enabled). The phone presents
  the secret once to register its own key; every later connection is authenticated by those keys.
- **Transport.** WebSocket from the host. Reachability, in order of effort:
  1. Same network: Bonjour discovery.
  2. Anywhere, no server of ours: over the user's Tailscale tailnet.
  3. Anywhere, zero setup: a small relay, end-to-end encrypted so it only forwards ciphertext.
- **Design references.** the reference app's iPhone companion (well reviewed) first, then the best AI assistant
  apps; research notes live in `research/companion-app.md`.
- **Security.** Pairing establishes a long-lived key pair per device. All traffic is end-to-end
  encrypted and authenticated (Noise or TLS with pinned keys), never trusting the network or a
  relay. Each paired device can be revoked from Settings. Permission answers from the phone are
  logged in the transcript as coming from that device.
- **Notifications.** While the app is in the background, wake-ups need APNs. Either via a minimal
  push relay, or CloudKit subscriptions (no server; needs an Apple Developer team and an iCloud
  container). Notification actions allow approving or rejecting a permission request from the
  lock screen.

## What this means for the Mac app now

- Every user action goes through model APIs (`SessionModel`, `AppModel`), never directly from views
  into connections, so the gateway can drive the same APIs as the UI.
- `Packages/ACP` builds for iOS; only `AgentProcess` (spawning agents) is macOS-only.
- New shared views avoid AppKit; platform-specific bits live behind small wrappers.
- Session identity is stable and serializable (`AgentDefinition.ID` + `SessionID`, plus
  `SessionContext.clientID` for live sessions), so the phone can address sessions.

## Open questions

- Relay: Tailscale-only first, or build the relay early? (Tailscale addresses already ride in the
  QR code; the relay is a `LinkAddress` kind waiting for a server.)
- Push: CloudKit (needs a developer team) or a push relay?
- Should the phone start tasks in new worktrees, or only in existing projects?
