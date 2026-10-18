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
content. The overall look comes from one place, the design system (`native/DesignSystem`).

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
`refs/native-checkpoints/*` so nothing is lost.

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

Agents can run on other machines: a Mac mini, a Linux server, later cloud sandboxes.
Each machine runs the same Native Host; the app connects to several hosts at
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
the terminal says how to enable it. By default Native writes the whole libghostty config itself,
so the terminal follows Native's design system and settings; "Use my Ghostty settings" loads the
user's own Ghostty config instead (read-only, with a few documented overrides), and "Import from
Ghostty" copies it into Native's settings once (`docs/terminal.md`).

## 2026-10-18: Expeditions

Native's take on long, multi-agent projects is called Expeditions. A lead agent proposes a route of assignments, the user approves it, and a crew of agents from any
providers works through it with review checkpoints, ending in a debrief and a pull request. It is
built from Native's own pieces (orchestration, goals, the workflow engine, worktrees, the durable
host) under its own vocabulary. Design: `docs/expeditions.md`.

## 2026-10-18: Seasonal channel icons are opt-in and expire locally

Beta has a dedicated amber/ivory compiled icon; Nightly uses its moon and starfield as the compiled
channel icon. (Superseded in part by "Celebrations are a plugin, and icons come in sets": the
Halloween switch and its timer are now the Celebrations plugin.) Halloween editions are opt-in from October 1 through November 7, inclusive, for
stable, beta and Nightly. They preserve the user's base icon and restore it at the closing boundary,
including when an app stays running or wakes after the season. The Gregorian date policy lives in
AppAppearance, with calendar boundary and time-zone tests. Mac Dock access and environment
notifications live in PlatformAppIcon, outside shared models and views.

Debug builds use a separate development icon identity, including its Halloween edition. Icon
identity lives in AppAppearance and stays separate from ReleaseChannel so a development build can
preview Nightly behavior without taking on a shipping build's icon. Original restores the compiled
development icon, retaining the system's Default, Dark, Clear and Tinted appearances.

## 2026-10-18: Celebrations are a plugin, and icons come in sets

Halloween moved out of the app icon preferences into the Celebrations plugin (`docs/celebrations.md`).
Plugins contribute two kinds of appearance data: `iconSets` (an icon per build channel in light and
dark, plus a Home mark or palette) and `celebrations` (identity, provenance, a calendar rule, display
windows and the icon set they use). A set no celebration uses is a plain app icon theme. Each entry
validates on its own, so a broken one never costs the plugin its other contributions.

One resolved celebration drives both the icon and Home, so two editions are never blended: a skip or
the user's choice first, then core dates over another's decorative window, then the user's order, then
the base. Dates are civil days with no time zone (`CivilDate`), so windows are counted in calendar
days and recomputed at midnight, on time-zone and clock changes, wake and activation. The engine,
validation and migration live in `Packages/AppAppearance` with the icon identity they build on;
coordination is `native/Celebrations/`, and only `native/Platform/PlatformAppIcon` touches the Dock.
The old `appIconHalloweenEnabled` switch becomes Halloween's selection, and turns the plugin on for
the people who had it. Halloween keeps its 1 October to 7 November window; Día de Muertos shows on
1 and 2 November, with 28 October to 3 November as a labelled decorative option, and changes only
Home until its icons exist (`docs/celebrations-artwork.md`).

Only Halloween's icons are bundled. Every other edition's icons are a pack published with each
release beside an index signed with the update key, fetched when the celebration is chosen and cached
per bundle id; small thumbnails ship in the app so the catalogue works offline. This keeps the app
over 100 MB lighter. An edition celebrates automatically only once its dates resolve: fixed dates,
weekday rules, day-of-year and the Easter computus are computed; other calendars come as cited annual
tables, and until then are listed as coming soon. Signature checking uses CryptoKit with the same
scheme and key as `HostUpdater`, which AppAppearance can't depend on because HostUpdater is Mac-only.

## 2026-10-18: Fair source under the Functional Source License

Native is licensed under FSL-1.1-ALv2. Anyone can read, fork, modify and use it, at work too, and
contribute back; the only use it rules out is offering a competing commercial product built from it.
Each release becomes Apache 2.0 two years after it's published. This keeps the project open and
friendly to fork without letting someone repackage the work as a rival app.

## 2026-10-18: Expeditions: agents plan, Native's engine schedules

Expeditions (`docs/expeditions.md`) are Native's take on long multi-agent objectives. A lead agent
proposes a route the user approves, but Native's engine, not the lead, starts builders and
reviewers from it: one source of truth for the overview, recovery and budgets, no reliance on an
agent calling coordination tools, and any provider in any role. Agents hand work back through
protocols in their replies (a route block, the goal status line, a verdict line) that Native
validates, and Native is the only writer of the shared artifacts. The engine is the UI-free
`Packages/Expeditions`, built from the goal loop and the workflow engine's shape, so it moves into
the durable host unchanged.

## 2026-10-18: Plugins live on hosts and reach every client

Plugins are installed on a host, the machine that runs agents, and every client (the Mac app, the iPad
app and the iPhone companion) gets that host's plugin catalog over the host protocol. A plugin's
contributions split by where they run:

- **Host-side:** agents, MCP servers, skills, workflow and automation engines, and sandboxed scripts.
  These run on the host only, and clients see their effects through sessions, as with any other
  agent work.
- **Client-side data:** themes, icon sets, celebrations and experiments. These are data, so the host
  sends the manifests and their assets to each client, which applies them locally: themes and Home
  marks everywhere, icon sets as the app icon on the Mac only (iOS can switch only between bundled
  icons), and experiments in each client's Labs.

A client can also hold appearance-only plugins of its own, for use without a host. Plugin code
never runs on iOS: built-in code plugins ship inside each app binary, and sandboxed code plugins
need the V8 runtime, which only hosts have.

## 2026-10-18: Transparency is three levels, Standard the clearest

Settings ▸ Appearance ▸ Transparency offers Solid, Subtle and Standard (the default, today's
look), read by every translucent surface through `\.dsTransparency` (`DesignSystem/Tokens`): the
sidebar lays its solid color over the system material, overlays (popovers, the undo toast, drag
previews) lay the overlay color over a blur, and floating controls (the composer, glass buttons)
use tinted, regular or no glass. Content stays opaque at every level. There is no level clearer
than the system's: on macOS 27 the split-view sidebar is an `NSGlassEffectView` tinted by the
wallpaper rather than showing windows through it, and its `.clear` style changes nothing visible
(checked in the running app); clear glass under the composer's text stops it reading. Reduce
Transparency always wins and forces Solid, and the row says so.

## 2026-10-18: Wool, a second light tone

Light mode can be drawn on Paper (white, the default) or Wool, a warm off-white (#F6F3EE page).
Wool is a token set, not a tint: every light neutral has its own Wool value, and text and status
colors step darker just enough to keep Paper's contrast on Wool's background (accent text still
clears 4.5:1 for every palette). Tokens resolve the tone from `\.dsLightTone`; dark mode is the same
under both. Plugin tone sets were left out: a tone is some twenty coordinated values plus text and
status shifts that must each keep their contrast, and Native has no way yet to check a set as a
whole beyond the per-value rules, so a broken one would degrade every screen.

## 2026-10-18: Code themes and a small lexer for highlighting

Code blocks, diffs and tool output use the code theme the user picks for each appearance
(`Packages/CodeThemes`, Native by default; Native's text roles keep their contrast on the design
system's surfaces, so it follows Wool). Highlighting is `CodeHighlighter` in that package: a
hand-written lexer per language family (comments, strings with escapes and multi-line forms,
numbers, keywords, types, calls, markup tags, Markdown structure, diff lines) for the 26 languages
agents write most, with no dependencies. It runs off the main thread, cached by content, and views
draw plain text first. Considered: tree-sitter (MIT, accurate incremental parsing, but a C library
plus a generated grammar per language, several MB each for TypeScript and C++, and highlight queries
to maintain; SwiftTreeSitter/Neon wrappers are BSD-3); highlight.js through JavaScriptCore or
Highlightr (BSD-3/MIT, a JS engine per highlight, ~1 MB of scripts, slower); Splash (MIT, Swift
only). A lexer covers what transcripts show, short self-contained fragments, without the build and
size cost. The seam is `CodeHighlighter.segments(_:language:)`; if accuracy falls short for a
language (TSX, C++ templates, nested string interpolation), tree-sitter is the upgrade, behind the
same seam, with a decision record for the dependency (it came: see "Tree-sitter for highlighting"
below). The terminal takes the theme through its one
input, `TerminalStore.appTheme`: chrome from the theme, ANSI colors from its roles.

## 2026-10-18: Hosts report and install their own updates

Update status is a property of a host, served over the host protocol, so an iPad or iPhone can see
and install updates for any host, including headless ones. On a Mac with the app, Sparkle updates the
whole app, host included; a standalone `native-host` (Linux, or a Mac without the app) updates
itself from a signed JSON host feed published beside the appcast, signed with the same Ed25519 key,
installing atomically through a symlink swap and rolling back a build that doesn't come up. Clients
can trigger an install but never choose what's installed. No new dependency: CryptoKit verifies on
Apple platforms; Linux will need swift-crypto, recorded when the host first builds there. See
`docs/releasing.md` ("Remote updates").

## 2026-10-18: Organizations manage Native through one policy layer; telemetry is opt-in and redirectable

Organizations configure Native with standard managed preferences (configuration profiles) that feed a
single `NativePolicy`; every feature asks it what's allowed, and Settings shows managed values as locked.
Native's own telemetry is anonymous product usage only, opt-in, never containing prompts, code, paths or
commands, and can be forced off by an organization, which can instead send the same events plus audit
events to its own OpenTelemetry collector. Design: `docs/enterprise.md`.

## 2026-10-18: Sentry for opt-in crash diagnostics

Use official `sentry-cocoa` **9.30.2**, pinned through SwiftPM, for crash persistence and symbolication
instead of maintaining signal handlers ourselves. `native/Telemetry/SentryTelemetry.start(dsn:)` is
called by Native's telemetry gate after consent and `policy.telemetry.native` permit it. Debug/dev
builds cannot start it. The DSN is `NATIVE_SENTRY_DSN` (`NativeSentryDSN` in Info.plist), set only for official
builds from a repository secret, so builds from source and forks never report to Native's Sentry.

`Packages/NativeDiagnostics` rebuilds reports from fixed error categories, timestamps, numeric thread
ids, instruction/load addresses, binary UUIDs, release and channel. It drops messages, paths, source
context, thread names, requests, user data and attachments. Automatic breadcrumbs, sessions, tracing,
logging, screenshots, hierarchy, replay and memory introspection are disabled. The only manual metrics
are finite numeric launch/hang durations, with all attributes removed. Stopping clears its offline
cache. Destination filtering keeps product-use events out of Sentry's queue and sent log.

Release publishing uploads dSYMs to FoxyCorps / `native` before publishing, using the protected GitHub
`SENTRY_AUTH_TOKEN` secret and checksum-verified official CLI **3.8.0**. It never uploads source bundles.
Dry runs don't upload; failed symbol uploads stop publication. Server-side IP scrubbing and a rule
removing `$user.geo.**` discard IP/geography enrichment Sentry adds after SDK filtering. See `docs/releasing.md`.

## 2026-10-18: Companion transport: Noise over TCP

Paired devices reach a host over TCP with a Noise handshake (`XX`, and `XXpsk3` with the one-time
pairing secret), built on CryptoKit (`Packages/NativeLink`, checked against the cacophony vectors).
TLS with pinned certificates through Network.framework was the alternative and lost on three
counts: CryptoKit can't make the self-signed certificates it needs (we'd hand-encode X.509), the
identities would live in the keychain, which prompts for every development build's new signature,
and pairing by a short typed code needs a PSK or PAKE that Network.framework's TLS doesn't offer
cleanly. Noise gives mutual authentication with pinned keys, forward secrecy and a pre-shared
pairing secret in one small, testable state machine that runs the same over TCP today and a
ciphertext-only relay later. No third-party code. See `docs/companion.md`.

## 2026-10-18: Tree-sitter for highlighting

Brayden chose accuracy, so code is now colored from a parse: `CodeHighlighter.segments(_:language:)`
keeps its seam, cache and background thread, and parses with tree-sitter through SwiftTreeSitter.
The lexer stays as the fallback, for languages without a grammar and for code a grammar loses its
place in (about one error node per line; a cut-off fragment, which tree-sitter often wraps in one
error node around text it parsed well, keeps its parse). Each grammar's highlight and
injection queries are copied into the package, pinned to the grammar's release, so precedence is
under our control: tree-sitter 0.25 lets the later pattern win, and several grammars still order
theirs for the old first-match rule (each copy says what changed). Injections color Markdown fences,
the inline half of Markdown, HTML scripts and styles, and Rust macro bodies; an embedded language
without a grammar uses the lexer for its range.

Dependencies, all exact pins through SwiftPM: tree-sitter runtime 0.25.10 (MIT), SwiftTreeSitter
0.10.0 (BSD-3-Clause), and grammars (MIT) for Swift, TypeScript and TSX, JavaScript, Python, Rust,
Go, JSON, Bash, YAML, TOML, HTML, CSS, Markdown, C, C++, Java, Kotlin and Ruby. JavaScript, Python,
CSS and YAML are pinned to their last releases whose Package.swift finds the external scanner
(later ones look it up relative to the working directory and fail as a dependency). The Markdown
and Kotlin queries derive from nvim-treesitter (Apache-2.0). `Packages/CodeThemes/NOTICE.md` lists
them all.

Cost, measured on an arm64 Release build: the app binary grows from 70.9 MB to 94.6 MB (`__TEXT`
32.1 MB to 54.7 MB), nearly all parse tables, which compress about tenfold (roughly 2.3 MB more to
download). By grammar: Swift 4.0 MB, Kotlin 3.9, C++ 3.3, Ruby 2.0, TSX 1.4, TypeScript 1.3, Bash
1.3, Rust 1.1, Markdown 0.7, C 0.6, Python, Java and JavaScript 0.4 each, the rest under 0.2; the
runtime and Swift API 0.25. Highlighting a 2,000-line TypeScript file takes about 35-45 ms against
the lexer's 12-14 ms (the parse is 6-7 ms; most of the rest is SwiftTreeSitter building Swift
objects per capture, which the C API does in about 5 ms), and a 50-line fragment about 1 ms
against 0.3 ms. A grammar's queries compile on first use: Swift's in about 100 ms, the others under
40 ms. Compiled queries for every grammar add about 7 MB of footprint, 6.3 MB of it Swift's (scratch
memory from tree-sitter's query analysis that malloc keeps); highlighting repeatedly stays flat.

Considered: keeping the lexer (it can't tell a TSX tag from a comparison, or code inside an
interpolation from the string around it); the C API without a wrapper (about twice as fast per
highlight, but our own predicate evaluation and pointer handling); SwiftTreeSitterLayer or Neon (an
incremental editing model a transcript doesn't need); the grammars' own query bundles (TypeScript
needs JavaScript's joined in, and their precedence varies); and an SQL grammar, left on the lexer:
its releases don't include the generated parser, and it alone would add 10.5 MB. Proposed, for
Brayden: leave Kotlin, C++ and Ruby on the lexer too, 9.2 MB for languages agents rarely write;
each comes out with its line in Package.swift, its case in `TreeSitterGrammar` and its queries.
