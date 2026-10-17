# Native

Native is a native macOS app for running coding agents (Claude Code, Codex, Cursor, and any agent a
plugin adds) side by side. It is a client of the [Agent Client Protocol](https://agentclientprotocol.com):
every agent runs as an ACP subprocess, and Native turns their sessions into tasks, transcripts,
approvals, goals and workflows. Many people and many agents contribute here, often in parallel, so
these rules exist to keep changes small, isolated and easy to review.

## Map

| Path | What lives there |
| --- | --- |
| `native/NativeApp.swift` | App entry point and composition root: scenes, menu commands, wiring |
| `native/Models/` | App state: `AppModel` (agents, workspace, sessions), `SessionModel` (one task) |
| `native/Plugins/` | Plugin API and registry; built-in plugins (agents, titles, notifications) |
| `native/DesignSystem/` | Tokens and shared components. All styling comes from here |
| `native/Views/` | Shared screens: transcript, composer, subagents, session, sidebar, root |
| `native/<Feature>/` | Self-contained features (Orchestration, Git, GitHub, Usage, Automation, Sounds, StatusBar, Settings) |
| `Packages/ACP` | ACP protocol, JSON-RPC connection, `SessionState` reducer. No UI. Builds for macOS and iOS |
| `Packages/*` | Other UI-free libraries (MCP server, git, gh) with their own tests |
| `docs/` | Architecture, keyboard map, decisions, plans. Read before changing behavior they describe |

`docs/architecture.md` describes how these fit together and where the layout is heading.

## Rules

- **Where code goes.** New feature: its own folder (`native/<Feature>/`), or a package if it has no
  UI. Don't add to another feature's folder; depend on its public types instead. Logic that can run
  without SwiftUI belongs in a package with tests.
- **Boundaries.** Packages never import the app. Features talk to models through their public API
  and to each other through protocols or plugins, never by reaching into internals. Every user
  action goes through a model method (views never talk to connections), so other clients (the
  companion app, the orchestration server) can drive the same actions.
- **Extend through plugins.** A new agent, title provider, MCP server or session hook is a plugin
  (`native/Plugins/Plugin.swift`), built in or as a `plugin.json` manifest. Don't special-case
  agents by name outside their plugin.
- **Design.** Colors, fonts, spacing, radii and motion come from `native/DesignSystem/`. No literal
  colors or sizes in feature views. Liquid Glass is only for the control layer (floating composer,
  toolbars), never for content. Light and dark must both look right.
- **Quality.** `docs/product-quality.md` is the bar for every feature: every state designed (what
  happened, undo, what next, never an empty nothing), one pattern per recurring situation, and
  failures handled so the user feels caught. Break your feature on purpose before calling it done.
- **Keyboard.** `docs/keyboard.md` is the source of truth for shortcuts. Change it first, and every
  new action needs a menu command or a shortcut.
- **Swift.** Swift 6 language mode with strict concurrency; the app target defaults to MainActor.
  Swift filenames and type names must be unique across the app target (it's one module until the
  migration to packages), so prefix feature-specific types: `UsageLimitBanner`, not `LimitBanner`.
  Type safety over stringly-typed data (`SessionID`, `AgentDefinition.ID`, enums with an
  unknown case for wire values). No force unwraps, `try!` or `as!`. One primary type per file, and
  split files that pass about 400 lines. Comments say why, not what.
- **Tests.** Package logic gets Swift Testing tests (`swift test` in the package), using real
  captured wire data where possible. Bug fixes start with a failing test or a reproduction.
- **Dependencies.** No third-party packages without a strong reason recorded in `docs/decisions/`.
  Never vendor other products' brand assets (logos, sounds); load user-owned copies at runtime.

## Build, test, run

```sh
xcodebuild -project native.xcodeproj -scheme native -derivedDataPath /tmp/native-dd/<you> build
(cd Packages/ACP && swift test)          # likewise for every package
swift format format -i <files you changed>   # style lives in .swift-format (4 spaces, 120 columns)
swift format lint --strict <files you changed>
```

Format only the files you change, so parallel work doesn't collide on whitespace. A repo-wide
`swift format lint --recursive --strict native Packages` becomes a required check once the one-time
formatting pass has landed.

Verify UI changes in the running app, not just the build. Several agents may run Native at once:
use your own DerivedData path, launch with `open -n`, automate only your own process (System Events
`first process whose unix id is <pid>`, never global keystrokes), screenshot with
`screencapture -x -l <windowid>`, and quit with `kill <pid>`.

Design references: the reference app (`<local reference>`, runnable rebuild `factory-clone`) and
the reference app (`<local reference>`, runnable rebuild `rebuild`). Read-only.

## Saving work (Kite)

The repo saves progress continuously with [Kite](https://github.com/binbandit/kite) (`kt`), so no
work is lost. Many agents share one working tree, so:

- **Save with a bare `kt`** from the repo root at every milestone (something compiles, a feature
  works, before a risky change), and at least every 20–30 minutes of work. It snapshots the whole
  tree, other agents' work included; that's intended.
- **Never stage** (`git add`) and never run `git commit`, `reset`, `checkout`, `restore`, `stash`,
  `switch` or `rebase`. A staged file would make everyone else's `kt` save only that file.
- **Never run `kt land`, `kt undo`, `kt go`, `kt publish`, `kt pr` or `kt ship`.** They rewrite or
  move shared history. The coordinator lands saves into conventional commits at integration points.
- If `kt` fails on `.git/index.lock`, another agent is saving: wait a few seconds and retry, up to
  three times. Never delete the lock file.
- Nothing secret and no third-party assets in the tree (research screenshots are gitignored).

## Pull requests

- One concern per PR, small enough to review in one sitting. Refactors and behavior changes go in
  separate PRs.
- Conventional commit titles: `feat(composer): queue follow-ups while a turn runs`.
- The description says what was wrong or missing and how the change addresses it, with screenshots
  for UI changes and the commands you ran to verify.
- Update the docs a change touches (`docs/keyboard.md`, `docs/architecture.md`, decisions) in the
  same PR. Builds, tests and `swift format lint --strict` on the changed files pass before review.
