# Decisions

Short records of decisions that shape Native, newest last. Add one when a choice would surprise a
future contributor or would be expensive to reverse.

## 2026-10-17: Native is an ACP client

Agents are driven over the Agent Client Protocol rather than each CLI's own format. One protocol
covers Claude Code, Codex, Cursor and anything else that speaks it, so Native's features
(transcripts, approvals, subagents, goals) work for every agent. Claude Code runs through
`@agentclientprotocol/claude-agent-acp`, pointed at the user's own `claude` so their version,
settings and login apply. Adapter versions are pinned and upgraded deliberately.

## 2026-10-17: macOS only, no App Sandbox

Native launches agent CLIs with the user's environment, and they read and write project files
anywhere. The sandbox would block both. The iPhone companion will be a separate target that reuses
the UI-free packages.

## 2026-10-17: Plugins from the start

Agents, title providers, MCP servers and session hooks are plugins, and Native's own features use
the same extension points. Third parties can add agents and MCP servers with a `plugin.json`
manifest. Out-of-process code plugins can come later on the same extension points.

## 2026-10-17: Liquid Glass only for the control layer

Following Apple's guidance, glass is for floating controls (composer, toolbars), never transcript
content. The overall look follows the reference app and the reference app, through the design system.

## 2026-10-17: On-device titles

Sessions are named from the first prompt with Apple's Foundation Models: free, private, fast and
consistent across agents. A user's own title wins, then the generated one, then the agent's.

## 2026-10-17: Queue by default, steer on demand

Messages sent while an agent works are queued by default (every agent supports it). Steering uses
the `_session/steering` extension where available. ⌘Return does the opposite of the setting.

## 2026-10-17: Orchestration over MCP

Cross-provider delegation (one agent starting and messaging tasks on another) is a local MCP
server Native hands to every session, with tokens tied to the calling session. Delegated tasks show
up exactly like agents' own subagents.

## 2026-10-17: GitHub through `gh`

GitHub features shell out to the user's `gh` CLI so their auth and hosts just work. Local git
operations use `git`. Neither uses a third-party library.

## 2026-10-17: Companion through an ACP gateway

The iPhone companion will be an ACP client of the Mac, reusing the same packages. See
`docs/companion.md`.

## 2026-10-17: Task worktrees under ~/.native

A task can run in its own git worktree so parallel agents never edit the same checkout. Worktrees
live at `~/.native/worktrees/<repo>/<slug>`, outside the repo so tools and file watchers don't see
them as part of the project. Before a worktree is removed, uncommitted work is saved to
`refs/native-checkpoints/*` so nothing is lost. This mirrors the reference app's proven layout.

## 2026-10-17: Durable by default

Agents keep working when the window closes or the app quits, and pick up after a crash, update or
reboot. A background host process (a login item registered with launchd) owns the agent processes,
sessions and everything that has to keep running: queues, goals, workflows, orchestration, limit
resumes, notifications and keep-awake. The app is a client of the host, the same way the iPhone
companion will be, so there is one gateway and one source of truth. Conversations stay in each
agent's own store (`session/load`); Native persists only its own state, in one store owned by the
host. A turn cut off by a crash is resumed by telling the agent it was interrupted, never by
silently replaying it. See `docs/durability.md`.

## 2026-10-17: Accent follows the app icon theme

Native's accent comes from the app icon theme the user picks (Original, Cobalt, Fern, Ember, Prism,
Arcade, Nightly), so the app matches its icon. Original is monochrome; color then means
status only. The brand mark is the interlock emblem from the app icon.

## 2026-10-17: Companion pairing by QR code

The iPhone companion pairs by scanning a QR code shown on the Mac. The code carries the host's
identity key and how to reach it, so pairing is a single scan and every later connection is
end-to-end authenticated.

## 2026-10-17: System icon appearances belong to macOS

Original restores the compiled `AppIcon.icon` stack so macOS controls Default, Dark, Clear and
Tinted appearances. Its default and dark artwork stay opaque; Mono uses native glass effects and
automatic tinting. Glass is an appearance, not a selectable theme. Existing Glass selections migrate
to Original. Other themes remain light/dark Dock image overrides through AppKit; they cannot retain
the bundled icon's native Clear/Tinted rendering. No private system preference keys or icon APIs are
used to imitate it.

## 2026-10-17: Experiments behind flags, variants as separate implementations

New UIs and designs ship to users as opt-in experiments before they become defaults. Every
experiment is declared once in a typed registry (id, title, description, stage: Labs or Beta,
default) and toggled in Settings ▸ Labs. An alternative design is its own implementation behind a
small style protocol (for example a bubble-style transcript beside the standard one), never `if`
branches scattered through shared views, so an experiment can be promoted, kept as a choice, or
deleted without touching the default path.
