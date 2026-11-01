# Native

Native is a native macOS app for running coding agents (Claude Code, Codex, Cursor, and any agent a
plugin adds) side by side. It is a client of the [Agent Client Protocol](https://agentclientprotocol.com):
every agent runs as an ACP subprocess, and Native turns their sessions into tasks, transcripts,
approvals, goals and workflows. Many people and many agents contribute here, often in parallel (see
[CONTRIBUTING.md](CONTRIBUTING.md) and [README.md](README.md)), so
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
| `Runtime/` | Non-Swift helpers embedded in the app (`Runtime/ScriptRuntime`: the sandboxed V8 script runtime) |
| `docs/` | Architecture, keyboard map, decisions, plans. Read before changing behavior they describe |

`docs/architecture.md` describes how these fit together and where the layout is heading.

## Rules

- **Secrets.** Native never reads other apps' secrets. Only Native-owned credential stores may be read; agent configuration without secrets and agent-reported authentication status remain supported.

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
  New or changed views come with a `#Preview` of their states (CONTRIBUTING.md, "Previews").
- **Platforms.** Native runs on Mac and iPad (`docs/architecture.md`, "Clients and hosts"). Models
  and shared views compile for both: no AppKit in them, and no process spawning outside
  `Packages/Exec` and the host. Platform-specific code goes behind an adapter in `native/Platform/`.
  Every action works with pointer, touch and keyboard, so hover-only affordances need a touch
  equivalent. The design system has the adapters: `DSPasteboard`, `DSTypography.platformFont`,
  `.dsHitTarget`, `DS.isTouchPlatform`.
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

`just` lists the everyday commands (build, run an isolated instance, test, format, lint, the iPad check, release checks); the commands it wraps are below.

```sh
scripts/dev/run-isolated.sh <you> --build   # compile check, in the same folder your instance uses
(cd Packages/ACP && swift test)          # likewise for every package
scripts/release/check.sh                  # Release and Nightly compile; run before landing #if DEBUG or build-setting changes
scripts/dev/install-hooks.sh              # once per clone: format + lint staged Swift, conventional commit titles
swift format format -i <files you changed>   # style lives in .swift-format (4 spaces, 120 columns)
swift format lint --strict <files you changed>
scripts/check-ios.sh native/<YourFeature>   # typechecks your folder and its app/package dependencies for iPadOS
```

Builds share this Mac with the person using it. `run-isolated.sh` builds through `scripts/dev/build-slot.sh`
(at most four app builds at a time, at a lower priority); run any other `xcodebuild` through it too. When
you're given a build Mac (`NATIVE_REMOTE_BUILD_HOST=user@machine`), run package builds there with
`scripts/dev/remote-swift.sh <you> <Package> build|test [swift args…]`, and tests too if it has full Xcode
(Command Line Tools lack Swift Testing's macros). Run tests here at low priority and filtered to yours:
`nice -n 10 swift test -j 4 --filter <Suite>`.

Run each build or test in the foreground in one tool call, with a timeout of at least 60 minutes
(including time queued for a build slot). Never background it and poll with sleep loops, `ps`, or
repeated `tail` calls. `build-slot.sh` blocks quietly after one queue message. If the tool has a
short maximum wait, use its continuation handle with the longest supported wait; do not restart
the command or inspect its process/log to see whether it finished. Read the log once after failure.

Keep `main` green: CI builds every PR, and a break you merged comes before anything else.

The app builds with zero warnings in Debug, Release and Nightly, and CI fails on any new one from our
files: fix yours in the same change (`scripts/check-warnings.sh /tmp/native-dd/<you>/build.log`).

The shell here is zsh: an unquoted `$files` is one argument, not a list, and `$sha:refs/...` reads as a
modifier. List files explicitly (or use an array), and write `"${sha}:refs/..."`.

Format only the files you change, so parallel work doesn't collide on whitespace. A repo-wide
`swift format lint --recursive --strict native Packages` becomes a required check once the one-time
formatting pass has landed.

Verify UI changes by rendering the real view, not just compiling it. For a change confined to one
view's appearance (type, color, spacing or drawing), render its `#Preview` states first with
`scripts/dev/render-previews.py` (CONTRIBUTING.md, "Previews"), inspect light and dark, and attach
those images to the PR. This is sufficient for that visual change. Build and drive the full app
when behavior, flows or window-level layout change, when a preview cannot faithfully show the
changed state, or before merge if the reviewer asks. Never replace real view rendering with a mock.

For full-app checks, several agents run Native at once, so use an isolated instance: `scripts/dev/run-isolated.sh <name> [-- app arguments…]` builds into
`/tmp/native-dd/<name>` with its own bundle id, defaults, Application Support and host, launches it,
and prints its pid and window id (`--quit` stops it, `--reset` also forgets its data). Automate only
that process through AX actions on it (`AXPress`, setting `AXValue`) or `CGEvent.postToPid`. Never
send System Events `keystroke`/`key code`, never bring a window to the front, and never use coordinate
clicks like `click at`: all of those land on whatever app has focus,
often someone else's. Never open other apps or windows on Brayden's Mac to test (Finder, editors, terminals, browsers): verify against a fake opener instead. Screenshot with `screencapture -x -l <windowid>`. Quit your instance (and any
render harness) as soon as a check is done; never leave apps running between checks, since many
agents share one Mac.
`scripts/dev/drive.sh <name>` does all of that automation scoped to your instance, and
[docs/playtesting.md](docs/playtesting.md) is the guide to running, driving and playtesting it.

Builds are about 6 GB each and the disk is shared: when your task is done, run
`scripts/dev/run-isolated.sh <name> --remove` for the one instance you used. Use one build folder
per agent: compile checks with `--build` reuse it. Keep extra scratch builds to the minute you need them. Profiling
with `xctrace` leaves 8-13 GB `instruments*.ktrace` files in `$TMPDIR` and large `.trace` bundles:
delete yours as soon as you've read the numbers. Always record with `--time-limit` and let xctrace stop
itself: if it's killed (a signal or `timeout`), its recording service keeps writing kernel trace with no
limit, over 100 GB within the hour. `lsof $TMPDIR/instruments*.ktrace` shows one still being written.
Never `xctrace record --launch` a Native binary: xctrace resolves it by bundle id to Brayden's installed
app. Launch your instance with run-isolated.sh and `--attach` to its pid. Never launch a Release or
Nightly build, whatever its bundle id: only Debug builds give the host a channel of their own, so a
Release build's host takes over Brayden's real host and sessions. For release-like numbers, build Debug
with `SWIFT_OPTIMIZATION_LEVEL=-O SWIFT_COMPILATION_MODE=wholemodule ENABLE_DEBUG_DYLIB=NO
ENABLE_TESTABILITY=NO` and say "optimized Debug".

When a check needs a real agent session, use Claude Code on Haiku at the lowest effort, and keep prompts
tiny. `run-isolated.sh` starts new tasks that way (`-defaultAgent claude-code
-agentDefaults.claude-code.model haiku -agentDefaults.claude-code.effort low`); otherwise pick Haiku and
Low in the composer's model picker. Use another agent only when the behavior under test belongs to that
agent (Codex's sandbox modes, say).

## Working on a change

Every change reaches `main` through a pull request. Work in a git worktree of your own, on your own
branch, never in the checkout at the repository root (that one is Brayden's):

```sh
git fetch origin main
git worktree add ../worktrees/<you> -b <type>/<topic> origin/main   # e.g. fix/turn-review
cp Config/Local.xcconfig ../worktrees/<you>/Config/   # signing settings, never committed; if present
cd ../worktrees/<you>
```

- Commit as you go with conventional messages, or save with [Kite](https://github.com/binbandit/kite)
  (`kt`) and group the saves with `kt land` before pushing. The history is yours until you push.
- Build and run from your worktree: `scripts/dev/run-isolated.sh <you> ...` builds that worktree.
- Before opening the PR, and again before merging, rebase on the latest `origin/main` and build, test
  and lint again.
- `main` ships to users every day (Nightly), so anything unfinished that merges stays behind a switch
  that defaults to today's behavior, and experiments come out before merge.
- Nothing secret and no third-party assets in the tree (research screenshots are gitignored).
- When your PR has merged, remove your worktree (`git worktree remove ../worktrees/<you>`) and your
  build (`scripts/dev/run-isolated.sh <you> --remove`).

## Pull requests

- Open a real PR, not a draft (`gh pr create`), so the review bot runs on it.
- One concern per PR, small enough to review in one sitting. Refactors and behavior changes go in
  separate PRs.
- Conventional commit titles: `feat(composer): queue follow-ups while a turn runs`.
- The description says what was wrong or missing and how the change addresses it, with screenshots
  for UI changes and the commands you ran to verify.
- Screenshots go on the orphan branch `pr-assets` (never merged), in a folder named for your branch
  (`feat-hosts-settings/`), embedded with `raw.githubusercontent.com` links. Fixture content only: no
  real names, tokens, personal data or paths outside the repo. Fetch and rebase before pushing to
  it, and delete your folder once the PR merges.
- Update the docs a change touches (`docs/keyboard.md`, `docs/architecture.md`, decisions) in the
  same PR. Builds, tests and `swift format lint --strict` on the changed files pass before review.
- No co-author lines, and nothing in titles, descriptions or commits about how the work was produced.
- The review bot comments on every PR. Check each finding against the source: fix the real ones, and
  answer the others with the reason. Fix CI failures, telling real breaks from known infrastructure
  flakes.
- Merge when CI and the review are green (`gh pr merge --squash --delete-branch`), unless your task
  says to stop and report.
