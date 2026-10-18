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
deleted without touching the default path. Small changes are gates (on/off at one call site) or
parameters (a typed value); alternatives are variants that replace an extension point's default.
Every experiment names an owner and a review date, so none linger. Plugins will contribute to the
same extension points later, as a second source. See "Experiments" in `docs/architecture.md`.

## 2026-10-17: Any machine can be a host

Agents can run on other machines: a Mac mini, a Linux server, later cloud sandboxes, like the reference app's
computers and droids. Each machine runs the same Native Host; the app connects to several hosts at
once, and every project belongs to one. Remote hosts are reached over SSH first (the user's own
keys, nothing new to trust), with other transports later. To keep this possible, nothing outside a
host runs commands or touches project files directly: code that shells out takes a `CommandRunner`
(`Packages/Exec`), so the same code runs on whichever machine owns the project.

## 2026-10-17: Native runs on iPad, connected to a host

The whole app runs on iPad, not just a companion. Agents can't run on iPadOS (no subprocesses), so
the iPad is a client of a host: a Mac running Native, or any other host. This makes the split in
"Any machine can be a host" the rule for every client: the UI is always a client of a host, and on
the Mac that host just happens to be local. Mac, iPad and iPhone share one SwiftUI codebase. The
iPad gets the full Mac experience adapted to touch, pointer and hardware keyboard. The iPhone gets
the companion layout of the same app (`docs/companion.md`). Pairing, transport and security are the
companion's: a QR code, then end-to-end authenticated connections.

## 2026-10-17: Minimal by default, shaped by the user

Like the Pi agent harness, Native starts with the fewest things turned on and lets each user shape
it into what they want. A fresh install is a clean place to talk to agents; everything else
(status bar items, sounds, Native's MCP tools, automations, experiments, extra agents) is a
built-in plugin the user turns on, from Settings ▸ Extensions or when Native offers it in context.
Agents can extend Native for the user too: built-in skills teach them how to write Native plugins.
Features are still designed in from the start; "off by default" is about what's on a new user's
screen, not about what Native can do.

## 2026-10-18: Releases on GitHub

Native ships through GitHub Releases. Each channel (stable, beta, nightly) publishes signed,
notarized builds as release assets, and the in-app updater reads a feed generated from those
releases. No servers of our own.

## 2026-10-18: Scripts run in a sandboxed V8 isolate

Code that agents or plugins hand Native to run (code mode's `run_script`, later code plugins and
scripted workflow steps) runs in a separate Rust helper embedding V8, never in the app. It is jitless,
sees only the tools it was given, and is signed into an App Sandbox with no file or network access.
Why Rust and V8, and the protocol, are in `docs/script-runtime.md` ("Decision: a Rust and V8 runtime").

## 2026-10-18: Sparkle for updates

Native updates itself with Sparkle 2, pinned to an exact version (2.10.0) and added through SwiftPM.
It's the standard for apps distributed outside the App Store: EdDSA-signed feeds and archives
(verified before extraction), an installer that replaces the bundle atomically and relaunches,
delta updates, and channels. Writing our own installer would mean owning the most
security-sensitive code in the app; the App Store is out because Native can't be sandboxed;
Squirrel.Mac is unmaintained. A custom user driver keeps Sparkle's windows out, so every update
state is Native's own UI (`native/Updates`). Sparkle is macOS-only and stays behind that folder:
only one file imports it, and iPad builds simply have no updater. Builds are Developer ID signed
and notarized. See `docs/releasing.md`.

## 2026-10-18: Nightly beside stable, beta as a channel

Native Nightly is a separate app (its own name, bundle id, feed and host) that installs beside
Native, like VS Code Insiders, so trying tonight's build never puts your daily driver at risk.
Beta is a Sparkle channel inside the stable feed: opting in from Settings costs nothing, and beta
users still get stable releases. Both feeds are GitHub release assets: stable and beta at
`releases/latest/download/appcast.xml`, nightly on a rolling `nightly` release. Release notes are
drafted from conventional commits; there's no hand-written changelog.

## 2026-10-18: The terminal is libghostty

Each task's terminal (`native/Terminal`) embeds libghostty, the library inside Ghostty (MIT): a
fast, correct VT emulator with a Metal renderer, CoreText font shaping, input method and kitty
keyboard support, and the same embedding API (`ghostty.h`) Ghostty's own macOS app is built on.
Writing an emulator is years of work; SwiftTerm draws with Core Graphics and lags on correctness;
xterm.js would mean a web view. The embedding API isn't declared stable, so the build pins one
Ghostty commit and the Zig it requires (`scripts/build-libghostty.sh`): currently `b1d2b7ef1`
(a 2026-09-28 tip build Ghostty shipped) with Zig 0.16.0, because Ghostty's last release (1.3.1)
pins Zig 0.15.2, which can't link on macOS 27. The script fetches both into
`~/Library/Caches/native-build` (never the user's own Zig or Ghostty) and builds a static
`libghostty.a` (ReleaseFast, no Sentry, no gettext) that the app links through a module map, plus
Ghostty's terminfo and shell integration, which the build phase copies into the bundle. Nothing
built or fetched lives in the repo. A build without it still compiles (`canImport(GhosttyKit)`) and
the terminal says how to enable it. Native writes the whole libghostty config itself and never
reads the user's Ghostty config, so the terminal follows Native's design system and settings.

## 2026-10-18: Expeditions

Native's take on long, multi-agent projects (the reference app calls theirs missions) is called Expeditions. A
lead agent proposes a route of assignments, the user approves it, and a crew of agents from any
providers works through it with review checkpoints, ending in a debrief and a pull request. It is
built from Native's own pieces (orchestration, goals, the workflow engine, worktrees, the durable
host) under its own vocabulary, never the reference app's. Design: `docs/expeditions.md`.

## 2026-10-18: Seasonal channel icons are opt-in and expire locally

Beta has a dedicated amber/ivory compiled icon; Nightly uses its moon and starfield as the compiled
channel icon. Halloween editions are opt-in from October 1 through November 7, inclusive, for
stable, beta and Nightly. They preserve the user's base icon and restore it at the closing boundary,
including when an app stays running or wakes after the season. The Gregorian date policy lives in
AppAppearance, with calendar boundary and time-zone tests. Mac Dock access and environment
notifications live in PlatformAppIcon, outside shared models and views.

## 2026-10-18: Fair source under the Functional Source License

Native is licensed under FSL-1.1-ALv2. Anyone can read, fork, modify and use it, at work too, and
contribute back; the only use it rules out is offering a competing commercial product built from it.
Each release becomes Apache 2.0 two years after it's published. This keeps the project open and
friendly to fork without letting someone repackage the work as a rival app.
