# Companion app plan

A Native companion for iPhone (and iPad), in the spirit of the reference app's: check on tasks away from
the Mac, approve permission requests, steer or queue follow-ups, start a task, and get notified
when something finishes or needs you. The Mac stays the host: agents, worktrees, credentials and
plugins live there. Not built yet; this records the decisions that shape the Mac app now.

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

- Relay: Tailscale-only first, or build the relay early?
- Push: CloudKit (needs a developer team) or a push relay?
- Should the phone start tasks in new worktrees, or only in existing projects?
