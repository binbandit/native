# Lean core

A plan for "a calm core, features you choose": what Native is made of today, what each part costs
in bytes and in trust, what organizations need from it, and how to reshape it so the app a person
installs is small and quiet, everything else is a module they turn on, and an administrator can
decide which modules and which agents exist at all. Audited 2026-10-20 against `main`.

## The stance

Minimal coding agents won people over by being light, simple and obvious: they did what you thought
they did, and you could build your own thing on top. Agent apps went the other way, dense and
feature-rich, with no way to make one your own. Native keeps its features (people want them
prebuilt) but makes each one a choice:

- **A calm core.** A fresh install is a place to talk to agents and approve their work. Nothing
  else runs, draws, listens or adds tools to a session until the user turns it on.
- **Features you choose.** Every feature is a module: on or off as a unit, and when off, absent
  (no state, no timers, no network, no menu items, no MCP tools), not hidden.
- **Small and boring to trust.** A small download, few dependencies, every fetched byte pinned and
  verified, one trust root for code we ship.
- **Enterprise first-class.** An administrator decides which modules and agents exist and which
  versions run, and everything Native fetches can come from their mirror or not at all.

## Findings

1. **"Minimal by default" (decisions, 2026-10-17) isn't what ships.** Of 11 built-in feature
   plugins, 8 start on, including the three the decision names as off: Sounds, Native's MCP tools
   (Orchestration) and the status bar. About 20 more features have no plugin identity, and about a
   dozen of those (terminal, Git, GitHub, project actions, modes, open-in, agent icon downloads...)
   can't be turned off at all.
2. **UI isn't part of the plugin system.** Plugins contribute agents, MCP servers, titles and hooks;
   pages, commands and status items come from three other registries (`AppSettingsPanes`,
   `CommandRegistry`, `StatusBarRegistry`), and sidebar entries from hand-written
   `if plugins.isEnabled(...)` checks in `RootView`. `NativeApp.init` constructs every feature's
   state (21 objects) whether or not it's used. Turning a plugin off rarely removes its UI.
3. **Size is three blobs, not features.** The script runtime (V8), libghostty and tree-sitter
   grammars, plus the icon catalog, are most of the app. Every Native feature module together is
   about 25 MB of code that compresses to about 8 MB. Lean core's feature work is about calm and
   choice; its size work is about three blobs.
4. **The largest supply-chain exposure is the agent adapters, not Swift packages.** Claude Code,
   Codex and Pi start through `npx --yes <adapter>@<version>`. Only the top package is pinned:
   transitive versions resolve fresh on every machine, install scripts are allowed, integrity is
   whatever the registry says, and Codex's adapter takes `@openai/codex ^0.160.1` and its other six
   dependencies as ranges. First use downloads about 650 MB, mostly agent binaries Native doesn't
   run (it points adapters at the user's own CLI).
5. **One shipped binary is built from an unverified download.** rusty_v8's build script fetches a
   37 MiB prebuilt V8 library from GitHub Releases and checks only that the URL matches; nothing
   checks its content. It's linked into `native-script-runtime`, which we sign and ship to everyone.
6. **Everything else Native fetches is in good shape.** Swift packages are exact pins with recorded
   revisions and checksummed binaries, Zig is SHA-256 pinned, Ghostty is fetched by commit, Cargo is
   `--locked`, and updates, host updates and celebration packs are Ed25519-signed.
7. **Enterprise allowlists trust self-declared ids.** `policy.plugins.allowed` and
   `policy.agents.allowed` match ids a manifest declares about itself, cover no versions, and
   built-in features mostly have no policy key at all.

## 1. Feature inventory

"Built as": **core** is always there; **built-in plugin** is a `NativePlugin` in `BuiltInPlugins.all`,
listed in Settings ▸ Extensions with a switch; **system plugin** always runs and isn't listed
(`SystemPlugins`); **hard-wired** is constructed in `NativeApp.init` or `RootView` with no plugin
identity.

### Core

| Feature | Where | Default | Off today? | Built as |
| --- | --- | --- | --- | --- |
| Transcript, composer, approvals, subagents, queue and steer | `native/Views`, `Packages/ACP` | on | no | core |
| Sidebar, tasks, projects, project settings | `native/Views/Sidebar`, `native/Projects`, `native/Models` | on | no | core |
| Add Agent, terminal sign-in, setup guides | `native/AgentCatalog` | on | no | core |
| Settings (in the main window) | `native/Settings` | on | no | core |
| Commands, palette (⌘K), remappable shortcuts | `native/Commands`, `Packages/NativeCommands` | on | no | core |
| Appearance: tones, accents, icon themes, code themes, highlighting (tree-sitter) | `native/Appearance`, `Packages/AppAppearance`, `Packages/CodeThemes` | on | no | core |
| Background host (agents outlive the app) | `native/Host`, `Packages/NativeHost`, `NativeHostHelper` | on | yes, one switch (next launch) | core |
| Clear conversation, earlier conversations | `native/ClearConversation` | on | no | hard-wired |
| AI instructions for titles, branches, commits, PRs | `native/AIInstructions`, `Packages/AIInstructions` | on | no | hard-wired |
| Help, keyboard help, Host Doctor | `native/Help`, `native/HostDoctor` | on | no | hard-wired |

### Agents

| Agent | Launch | Default | Off today? | Built as |
| --- | --- | --- | --- | --- |
| Claude Code | `npx --yes @agentclientprotocol/claude-agent-acp@0.93.0`, runs the user's `claude` | on when `claude` is on PATH | yes | built-in manifest plugin |
| Codex | `npx --yes @agentclientprotocol/codex-acp@2.2.2`, runs the user's `codex` | on when installed | yes | built-in manifest plugin |
| Pi | `npx --yes pi-acp@0.0.34`, runs the user's `pi` | on when installed | yes | built-in manifest plugin |
| Cursor, OpenCode, Copilot | the user's own CLI (`cursor-agent acp`, `opencode acp`, `copilot --acp`) | on when installed | yes | built-in manifest plugins |
| Any agent from `~/.native/plugins/*/plugin.json` | the manifest's command | on | yes | manifest plugin |

### Built-in feature plugins

| Feature | Where | Default | Off today? | What "on" adds |
| --- | --- | --- | --- | --- |
| On-device titles | `native/Plugins`, `Packages/SessionTitling` | on | yes | Apple Intelligence titles, in the host too |
| Sounds | `native/Sounds` | **on** (decision says off) | yes | sounds on finish, needs-you, failure |
| Orchestration: Native's MCP server | `native/Orchestration`, `Packages/Orchestration`, `Packages/MCPServer` | **on** (decision says off) | yes | a `native` MCP server in every session: tasks on other agents, `run_script`, `setup_status`, `get_skill` |
| MCP servers | `native/MCP`, `Packages/MCPClient` | on | yes | one MCP list across agents, handed to every session |
| Skills | `native/Skills`, `Packages/Skills` | on | yes | one skill list across agents, installs from git and the skills registry |
| Usage | `native/Usage` | on | yes | limit warnings, resume at reset, context breakdown, notifications |
| Goals and workflows | `native/Automation`, `Packages/Automation` | on | yes | goal loops, multi-agent workflows, Workflows in the sidebar |
| Automations | `native/Automation` | off | yes | scheduled and event-triggered tasks |
| Expeditions | `native/Expeditions`, `Packages/Expeditions` | off | yes | long multi-agent projects |
| Search | `native/Search`, `Packages/Search` | on | yes | SQLite FTS5 index of every session, live and past |
| Celebrations | `native/Celebrations` | off | yes | dated icon and Home editions, downloadable packs |

System plugins, always on and not listed: Organization Policy (`native/Policy`), Telemetry session
hooks (`native/Telemetry`), Task Scripts session hooks (`native/TaskScripts`).

### Hard-wired features

| Feature | Where | Default | Off today? |
| --- | --- | --- | --- |
| Git: status, diffs, commit, worktrees, branch names, clean up merged | `native/Git`, `Packages/Git` | on | no (settings tune it) |
| GitHub: PR list and badges, create and merge, private PR questions, open PR as task | `native/GitHub`, `native/PullRequestTasks`, `Packages/GitHub` | on (needs `gh`) | no |
| Terminal (libghostty) | `native/Terminal`, `Packages/Terminal` | on | no |
| Project actions (Test, Install...) | `native/ProjectActions`, `Packages/ProjectActions` | on; repository actions need trust | no |
| Task scripts (`.native/<event>.sh`, user scripts) | `native/TaskScripts`, `Packages/TaskScripts` | user scripts on; repository scripts need trust per project | policy, per project |
| Script runtime (V8, sandboxed helper) | `Runtime/ScriptRuntime`, `Packages/ScriptRuntime` | on through Orchestration | policy only (`policy.scripts.enabled`) |
| Modes (Build, Plan, Ask, custom, per project) | `native/Modes`, `Packages/Modes` | on | no |
| Status bar | `native/StatusBar` (own registry) | shown, 5 items | yes: hide the bar or each item |
| Keep awake | `native/KeepAwake` | mode Off | yes (mode) |
| System notifications | `native/Notifications`, Usage | on for long work, needs-you, limits | per kind |
| Dock badge | `native/Wiring/DockBadgeWiring.swift` | on | setting |
| Open in (editors, Finder) | `native/OpenIn` | on | no |
| Companion pairing (Noise over TCP) | `native/Companion`, `Packages/NativeLink` | listener off until first pairing | yes, and policy |
| Remote hosts | `native/Hosts` | on (none connected) | policy only |
| Updates (Sparkle) | `native/Updates` | daily check | yes, and policy |
| What's New | `native/WhatsNew` | on | yes |
| Labs (3 experiments, all off) | `native/Experiments`, `Packages/Experiments` | on | policy only |
| Telemetry (Sentry for us, OTLP for organizations) | `native/Telemetry`, `Packages/Telemetry`, `Packages/NativeDiagnostics` | off until opt-in | yes, and policy |
| Agent icons from the ACP registry | `native/AgentIcons` | on: fetches an index and SVGs at launch when not cached | no |
| Project icons (favicon and SVG detection) | `native/ProjectIcons` | on, local files only | per project |
| Launch metrics (the perf driver is Debug only) | `native/Performance` | on | no |

## 2. Size

Figures are from `docs/app-size.md`'s link map of a stable release dry run on **2026-10-19**
(Release, stripped, arm64), plus the script runtime measured again on **2026-10-20** (41.37 MB
installed, 15.02 MB zipped, unchanged). A fresh build wasn't run for this plan; the ranking is what
matters, and it hasn't moved.

### The whole app (2026-10-19, after Kotlin, C++ and Ruby went to the lexer)

| | Installed | Download |
| --- | --- | --- |
| Whole app | 107.5 MB | 42.7 MB (update archive) |
| App binary | 53.2 MB | about 16 MB |
| Script runtime (V8 helper) | 41.4 MB | 15.0 MB |
| `Assets.car` (24 alternate icons) | 6.8 MB | 6.6 MB |
| Host helper (`Native Host.app`) | 2.7 MB | 1.1 MB |
| Frameworks (Sparkle, Sentry's loader) | 2.7 MB | 1.0 MB |
| Fonts (Geist, Geist Mono), terminfo, the rest | 0.7 MB | 0.6 MB |

Most updates are deltas: 2.7 MB between two release builds an hour apart.

### Ranked costs

| # | What | Installed | Download | Ships to everyone? |
| --- | --- | --- | --- | --- |
| 1 | V8 script runtime (ICU data 10.8, optimizing compilers it never runs 11.4, the rest of V8 12.3) | 41.4 MB | 15.0 MB | yes, used only by `run_script` and script steps |
| 2 | libghostty (Zig core 7.1 including 3.05 MB of embedded fonts; shader compilers 3.5) | 12.4 MB | about 4 MB | yes |
| 3 | tree-sitter grammars (12 left; Swift 4.2, TSX 1.4, TypeScript 1.4, Bash 1.4, Rust 1.1...) | about 12.6 MB | about 1.3 MB (parse tables compress tenfold) | yes |
| 4 | App icons (24 alternates, lossless PNGs) | 6.8 MB | 6.6 MB | yes; about 1.9 MB are channel icons other channels never show |
| 5 | Native's own code (`native/`) | 16.4 MB | about 5 MB | yes |
| 6 | Native's Swift packages | about 8.5 MB | about 3 MB | yes |
| 7 | Host helper | 2.7 MB | 1.1 MB | yes |
| 8 | Sentry (static) | 1.95 MB | about 0.7 MB | yes, started only after opt-in |
| 9 | Sparkle | about 2 MB | about 0.8 MB | yes (Mac) |

Features, by their code (app folder plus package): GitHub 2.65 MB, Views 2.47, Design System 1.74,
Automation 1.48, Git 1.41, Expeditions 1.24, ACP 0.86, Models 0.83, Usage 0.72, MCP 0.70; every
other feature is under 0.6 MB. No feature module is worth downloading separately; the three blobs
and the icons are.

Outside the budget, on the user's disk: the adapters `npx` installs on first use, about 650 MB
(section 3).

## 3. Supply chain

Everything Native runs that it didn't build from its own source, when it's fetched, and how it's
checked.

### At build time

| Item | Pinned | Integrity | Risk | Done | To do |
| --- | --- | --- | --- | --- | --- |
| Sparkle 2.10.0 | exact, revision in `Package.resolved` | SwiftPM checksum on a prebuilt xcframework | low; a prebuilt binary in the updater | exact pin, checksum, signed feed | lock resolution in release builds (below) |
| sentry-cocoa 9.30.2 | exact | SwiftPM checksum on a prebuilt static xcframework | low; 1.95 MB of prebuilt code in every app, started only after consent | exact pin, checksum, starts only after opt-in | none |
| tree-sitter 0.25.10, SwiftTreeSitter 0.10.0, 15 grammars | exact, revisions | git revision | medium; megabytes of generated C parsing agent output in-process, one grammar from a single maintainer (`tree-sitter-swift`, a `-with-generated-files` tag) | exact pins, queries copied and reviewed, NOTICE | review generated-parser diffs on each bump |
| Zig 0.16.0 (builds libghostty) | version | SHA-256 per arch in `build-libghostty.sh` | low | done | none |
| Ghostty `b1d2b7ef1` and its Zig packages | full commit | git commit; Zig verifies each package against `build.zig.zon` hashes | low | done | none |
| Xcode Metal toolchain | Xcode's | Apple-signed | low | done | none |
| Rust crates (101, for the script runtime) | `Cargo.lock`, `v8 = "=150.4.0"` | crates.io checksums, `cargo build --locked` | low | done | a `rust-toolchain.toml`; the compiler isn't pinned |
| **rusty_v8's prebuilt `librusty_v8.a` (37 MiB)** | by crate version | **none**: `build.rs` treats the URL as its "checksum" | **high**: unverified code linked into a binary we sign and ship | the `--sandbox` path builds V8 from SHA-256-pinned inputs | fetch it in `build-script-runtime.sh`, check a pinned SHA-256, hand it over with `RUSTY_V8_ARCHIVE` (the hook `--sandbox` already uses), or drop V8 (section 5) |
| sentry-cli 3.8.0 (dSYM upload) | version | SHA-256 | low | done | none |
| GitHub Actions (`actions/checkout@v5`, `cache@v4`, `upload-artifact@v4`) | major tag | none | medium; the release job holds signing and notarization secrets | first-party only, Dependabot | pin by commit SHA |
| CI caches of libghostty and the runtime | key on script and lockfile hashes, with prefix `restore-keys` | none | medium; a release links a library some earlier run built | caches are per-branch | release builds them fresh, or checks them against recorded hashes |
| Package resolution in release builds | `release.sh` and `check.sh` don't pass `-disableAutomaticPackageResolution` | | low | | pass it, so a resolved-file mismatch fails instead of re-resolving |
| Dependabot | covers GitHub Actions only; its comment says Sparkle is the only dependency | | low | | add the `swift` and `cargo` ecosystems for security bumps |

### At runtime

| What | When | Pinned | Integrity | Risk | Done | To do |
| --- | --- | --- | --- | --- | --- | --- |
| **Claude Code adapter** (`claude-agent-acp@0.93.0`) | first start, and whenever npx's cache lacks it | top package exact; its 4 direct deps exact; 115 packages in all, transitive ranges resolved per machine | sha512 from the registry, which vouches for itself | **high**: a hijacked transitive package reaches every new install; install scripts allowed; runs with the user's login environment and drives their `claude` | version pinned; `skippingNpx` runs the cached binary without npm in the middle | ship a lockfile, install with scripts off (section 5) |
| **Codex adapter** (`codex-acp@2.2.2`) | as above | top package only: all 7 direct deps are ranges, including `@openai/codex ^0.160.1` | as above | **high**, and the "pin" doesn't pin the codex binary it bundles | as above | as above |
| **Pi adapter** (`pi-acp@0.0.34`) | as above | 9 packages, a 0.0.x adapter | as above | medium | as above | as above |
| Adapter downloads, by size | first start | | | about 650 MB on disk: 305 MB Claude (238 MB is the agent SDK's own platform binary), 335 MB Codex (318 MB is a codex binary), 7 MB Pi | | check whether the bundled agent binaries can be omitted when the adapter runs the user's CLI |
| Cursor, OpenCode, Copilot | never; the user's CLI | | | user's own | | |
| Manifest plugins (`~/.native/plugins`) | at launch | no | no | by design they run any command; `policy.plugins.allowed` matches a self-declared id, so any folder can claim an allowed one | load failures listed, per-plugin switch | policy entries with content hashes; an organization catalog with a signed index (`docs/enterprise.md`, Later) |
| MCP servers from plugins or the user | per session | the user's | no | the user's own choice | `policy.mcp.allowed/blocked/required` | none |
| Skills from git or the skills registry | when the user installs one | records the revision; installs a branch tip by default | no | medium; a skill is instructions and sometimes scripts an agent runs | staged and shown before install, undoable | a policy key to forbid remote installs or limit sources |
| Agent icons (`cdn.agentclientprotocol.com`) | at launch when not cached, weekly refresh | no | no | low for code (a restricted SVG reader, external entities off); a third-party request with no user action and no policy switch | monogram fallback | fetch only for agents that are installed or being added; a policy switch; part of an offline policy |
| Celebration packs | when the user picks a celebration | per release | Ed25519-signed index, SHA-256 per pack | low | done | none |
| App updates (Sparkle) | daily | per release | EdDSA on the feed and archive, Developer ID, notarized | low | done; `policy.updates.feedURL` for a mirror | none |
| Standalone host updates | per host | per release | Ed25519 and SHA-256, atomic install with rollback | low | done | none |
| Repository task scripts and actions | at task events | the repository's | no | medium; whoever commits to the repo writes them | off until trusted per project, read from the main checkout only, policy key | none |
| Scripts agents hand to `run_script` | on call | | | contained | App Sandbox with no files or network, jitless, tools bound per call | none |
| Telemetry | only after opt-in | | | | allowlisted typed events | none |

### What happens if npm serves a malicious adapter

Today, a new machine (or a cleared npm cache) installs whatever versions of the adapter's
transitive dependencies are newest within their ranges, runs their install scripts as the user,
and Native then starts the adapter with the user's login environment: API keys, `gh` and cloud
credentials, SSH agent. Nothing in Native would notice. The exact top-level pin protects only
against the adapter's own maintainers publishing a bad version under the same number, which npm
doesn't allow anyway. The fix is to pin the whole tree (section 5, "Adapters").

## 4. Enterprise

### What exists

- **One policy layer.** `Packages/NativePolicy` reads 22 `policy.*` keys from managed preferences
  (configuration profiles on the Mac, managed app configuration on iPad), validates them, reports
  bad values instead of failing, and Settings shows managed values as locked. A sample profile is
  `docs/enterprise/native-policy.mobileconfig`.
- **Agents:** an allowlist by id and extra environment per agent (routing Claude Code through a
  cloud provider, say). **MCP:** allow, block and required servers by name or command pattern,
  translated into each agent's own terms. **Skills:** blocked by name. **Permissions:** forbidden
  modes.
- **Features with keys:** script runtime, task scripts (user and repository), Labs, companion,
  remote hosts, updates (feed, channels, off), search retention, shortcuts, AI instructions,
  telemetry (ours and theirs).
- **Telemetry:** ours opt-in, theirs to their own OTLP collector, a local log of what was sent.
- **Audit:** the host keeps an activity journal (sessions, prompts, approvals and from which device,
  recoveries, updates). Exporting it to the organization's collector is designed, not built.
- **Signing:** Developer ID, notarized, Ed25519-signed feeds; the host accepts only peers signed by
  the same team (`CodeSignatureVerifier`).

### What's missing

| Need | Today | Gap |
| --- | --- | --- |
| Decide which features exist | keys for 6 features; `policy.plugins.allowed` covers manifests and exempts built-ins | no key for terminal, GitHub, orchestration, automations, expeditions, sounds, search, agent icon downloads, skills installs... |
| Allowed agents and versions | `policy.agents.allowed` by id | no adapter version or command pin, no lockfile, no registry mirror; ids are self-declared |
| Allowed plugins | by self-declared id | no content hash or signer |
| Offline and mirrored installs | Sparkle feed URL | adapters come from public npm (or the user's own `.npmrc`), icons from a public CDN, celebration packs from GitHub; no single "nothing leaves the building" switch |
| Audit export | journal only | OTLP export of audit events, plus module and policy changes |
| A bill of materials | none | security reviews ask for one; everything needed is already in lockfiles |
| SSO | n/a: Native has no accounts; agents sign in to their own providers | none needed now; shared Linux hosts would need it (Later in `docs/enterprise.md`) |

### What a module design must preserve or enable

- **One question, one answer.** "Is this module allowed, required, and on?" is answered by
  `NativePolicy` plus the user's choice, in that order, for built-ins and installed plugins alike.
- **Managed means visible.** A blocked module shows in Extensions as "Not allowed by your
  organization"; a required one shows on and locked. Never silently absent.
- **Off means off on the host too.** Host-side modules (orchestration, automations, MCP, skills,
  search indexing) are switched where they run, so a policy applies whether or not an app is open.
- **Versions are policy.** Which adapter version, from which registry, with which lockfile, is an
  administrator's decision, not only a build constant.
- **Data, not code.** Policy stays declarative; a bad value is reported and ignored.

## 5. The plan: a calm core, features you choose

### What's core

Core is what every user needs to talk to agents and keep them safe, and nothing else:

- ACP client, transcript, composer, approvals, subagents, queue and steer.
- Projects, tasks and the sidebar; Add Agent and sign-in.
- Settings, commands and the palette, shortcuts, appearance and code highlighting.
- The background host, policy, updates, crash diagnostics (still opt-in).

Everything else is a module. Most are built in; some start on (section "Onboarding").

### Modules are plugins with UI

There is one extension system: `NativePlugin`. It already carries identity, an on/off state the user
owns, a default, policy, experiments, session MCP servers and hooks. A module is a plugin that also
contributes to the app's UI while it's on:

```swift
/// A plugin that also adds to the app while it's on. Everything it returns is gone when it's off.
protocol FeatureModule: NativePlugin {
    /// Other modules it needs (PR tasks need Git and GitHub). Turning it on offers to turn them on.
    var requires: [PluginID] { get }
    /// Builds the module's state and says what it adds. Called when it's turned on, never before.
    @MainActor func activate(in context: ModuleContext) -> ModuleContributions
}

/// The few places a module can add to. Each place reads only from the registry.
struct ModuleContributions {
    var settingsPanes: [SettingsPane] = []          // Settings ▸ Extensions group
    var commands: [NativeCommand] = []              // menus, palette, shortcuts
    var statusItems: [AnyStatusBarItem] = []        // the status bar
    var sidebarItems: [SidebarContribution] = []    // Workflows, Expeditions, Pull Requests, Search
    var sessionPanels: [SessionPanelContribution] = [] // the inspector: Changes, Terminal, Context
    var taskAccessories: [TaskAccessoryContribution] = [] // badges on task rows: PR state, CI
    var deactivate: @MainActor () -> Void = {}      // stop timers, listeners, processes
}
```

Seven places, each already a seam today (`SettingsPane`, `CommandRegistry`, `StatusBarRegistry`,
`RootView`'s sidebar, `InspectorRoom`, `AppTaskRowAccessory`), so the work is moving their sources
behind `PluginRegistry`, not inventing them. `ModuleContext` hands a module the app model, the
policy, its host and the shared services other modules expose through protocols, so features still
never import features (`docs/architecture.md`); the app's `Wiring/` keeps connecting them.

Rules every module follows:

- **Off means absent.** No state object, timer, listener, process, network request, menu item,
  status item, sidebar entry or MCP tool. Its row in Extensions stays, saying what it does.
- **On is lazy.** `activate` runs when the module is turned on or first needed, not in
  `NativeApp.init`, which shrinks to core.
- **One switch.** Settings, commands and the status bar never check `isEnabled` themselves; they
  render what the registry hands them.
- **Where it runs decides where it's switched.** Host-side modules are switched on the host, which
  every client shows (the paired-device "Can Turn Plugins On and Off" grant already exists).
- **Manifest plugins stay data.** `plugin.json` keeps contributing agents, MCP servers, workflows,
  themes, icon sets, celebrations and experiments. UI contributions from code come later, from
  sandboxed code plugins (Phase 7), never from code loaded into the app.

### The modules

| Module | Contents | Starts | Requires |
| --- | --- | --- | --- |
| Git | changes, diffs, commit, worktrees, clean up | on (Essentials) | |
| Terminal | per-task terminal | on (Essentials) | |
| Notifications | system notifications, Dock badge | on (Essentials) | |
| Usage | limits, resume at reset, context breakdown | on (Essentials) | |
| On-device titles | | on (Essentials) | |
| Search | session index | on (Essentials) | |
| GitHub | PRs, badges, create and merge, PR questions, PR tasks | off, offered when a project has a GitHub remote and `gh` | Git |
| Modes | Build, Plan, Ask, custom | off, offered from the composer | |
| Project actions | quick actions per project | off, offered when a project has scripts | |
| Task scripts | user and repository scripts | off | |
| MCP servers | one list across agents | off, offered on the first MCP mention | |
| Skills | one list across agents, installs | off | |
| Orchestration | Native's MCP tools in every session | off | |
| Code mode | `run_script`, scripted workflow steps | off | Orchestration |
| Goals and workflows | | off | |
| Automations | | off | Goals and workflows |
| Expeditions | | off | Goals and workflows, Git |
| Status bar | the bar and its items | off | |
| Keep awake | | off | |
| Sounds | | off | |
| Open in | editor and Finder buttons | off | |
| Companion and remote hosts | pairing, connecting to hosts | off | |
| Celebrations | | off | |
| Labs | experiments | off | |
| What's New | | off | |
| Agent icons | registry icons instead of monograms | off; installed apps' own icons still apply | |

The "Starts" column is a proposal for Brayden; the mechanism doesn't depend on it.

### Onboarding and Settings

- **First launch** asks one question beside "Add a project": how much Native to start with.
  **Just agents** (core only), **Essentials** (the default: Git, terminal, notifications, usage,
  titles, search) or **Everything**. "Customize" lists every module with one line on what it does
  and what it costs: "adds tools to every session", "uses the network", "runs in the background".
- **In context, once.** A module offers itself where it would help (a PR link in a transcript, a
  usage limit reached, the composer's mode button), the way the Workflows page already offers
  Automations. Declined offers aren't repeated.
- **Settings ▸ Extensions** becomes the one list: built-in modules grouped by what they're for, then
  installed plugins, each with its switch, its cost badges, what it requires, and "Managed by your
  organization" where policy decides. A module's own settings page appears in the Extensions group
  only while it's on.
- **Existing users keep everything.** The first launch after the change records today's state as
  explicit choices (`PluginRegistry` already prefers a choice over a default), so nothing they use
  disappears; only new installs start from a preset.

### Enterprise policy for modules

| Key | Effect |
| --- | --- |
| `policy.plugins.allowed` / `policy.plugins.blocked` | Now covers built-in modules too. Blocked: absent and labelled. Allowed: the only ones that can exist. |
| `policy.plugins.required` | On and locked (Usage, Search with retention, an internal MCP plugin). |
| `policy.plugins.defaults` | The starting state for new users; they can change it. |
| `policy.plugins.allowed` entries as `{id, sha256}` | A manifest plugin loads only when its `plugin.json` matches. |
| `policy.agents.adapters` | Per agent: the adapter package and version, and the lockfile to install it from (an organization can pin an older or internal build). |
| `policy.network.registry` | The npm registry adapters install from (an internal mirror). |
| `policy.network.offline` | Native itself fetches nothing but updates (from `policy.updates.feedURL`): no icons, celebration packs, skills registry or on-demand components. |
| `policy.components.baseURL` | Where on-demand components (section "Heavy modules") come from. |

Today's feature keys (`policy.scripts.enabled`, `policy.labs.enabled`, `policy.companion.enabled`,
`policy.remoteHosts.enabled`) stay and map onto their modules, so existing profiles keep working.
Module and policy changes join the audit journal and its export.

### The plugin catalog (decided: the first phase)

One place to find everything Native can add, owned by Native and safe by construction:

- **An official, Native-owned plugins repository.** Each plugin is a folder with its `plugin.json`
  and assets, reviewed by pull request.
- **A signed index.** Published with each change and signed with Ed25519 (EdDSA), the scheme and
  key handling the update feed and celebration packs already use. Native verifies it before reading
  it.
- **Pinned content.** Each entry names a commit and a SHA-256 of the plugin's files; Native installs
  only bytes that match.
- **An honest install screen.** Before anything installs, it shows what the plugin adds: each agent
  and the exact command it runs, each MCP server and its command or URL, workflows, themes, icon
  sets and celebrations.
- **No silent updates.** A new version is offered with what changed in those same terms; the user
  installs it, or doesn't.
- **Agent plugins pin their adapters.** An agent entry carries its adapter's version and lockfile
  with integrity hashes, installed as in "Adapters" below, which closes the `npx` risk for every
  catalog agent.
- **Enterprise.** Policy can turn the catalog off, allowlist plugins from it, or point Native at a
  mirror of the repository and its index (`policy.catalog.enabled`, `policy.plugins.allowed`,
  `policy.catalog.indexURL`).
- **Data moves out of the app first.** Non-default data leaves the bundle for the catalog: extra
  themes, icon sets, celebrations, sample workflows, experiments, and agents beyond the core few.
  Built-in code features stay in the binary, off by default, but are listed in the same catalog
  with the same switch, so there's one place to choose from.

### Adapters

Pin the whole tree, keep npm out of the launch path, and let an organization choose:

1. **Lockfiles in the app.** Each built-in adapter gets a `package-lock.json` (every transitive
   package with its sha512), generated by a script and reviewed in the pull request that bumps it.
   They're a few KB each and ship inside the signed app.
2. **Native installs, npm verifies.** On first start Native runs `npm ci --ignore-scripts` from that
   lockfile into its own folder (`Application Support/Native/Adapters/<name>@<version>`), so npm
   checks every package against our hashes rather than the registry's, and no install script runs.
   Then it launches `node <bin>` directly, which also retires `NpxLaunch`'s cache lookup.
3. **Smaller first start.** Check whether the agent binaries the adapters bundle (238 MB and 318 MB)
   can be left out with `--omit=optional` when the adapter is pointed at the user's own CLI. If so,
   first use drops from about 650 MB to about 40 MB.
4. **Policy.** `policy.agents.adapters` and `policy.network.registry` choose the version, lockfile
   and mirror; an air-gapped organization pre-stages the folder through MDM.
5. **Later.** Publish each adapter as one signed bundle per release, verified like celebration packs,
   so npm leaves the runtime path entirely (Node stays).

### Heavy modules: download, or ship off

The trade-off: a module left out of the bundle saves its bytes for people who never use it, but
adds a second way code reaches the machine, which needs its own pinning, signing, mirroring and an
offline story. A module shipped in the bundle but off costs disk and the first download, but has one
trust root (the notarized app) and costs nothing on most updates, since updates are deltas (2.7 MB
for a typical one, `docs/app-size.md`) and an unchanged module adds nothing to a delta.

| Option | Installed | Download | New trust paths | Notes |
| --- | --- | --- | --- | --- |
| Today: V8 runtime and terminal in the bundle | 107.5 MB | 42.7 MB | none | |
| Runtime as an on-demand, hash-pinned component | 66 MB | 27.7 MB, plus 15 MB for those who turn on Code mode | one, same keys as updates | V8's prebuilt still needs pinning |
| Runtime on JavaScriptCore | 66 MB | 27.7 MB | none; fewer (no Rust, no V8 prebuilt) | Swift rewrite, slower numeric loops |
| V8 rebuilt without its compilers | 91.3 MB | 37.8 MB | we publish our own V8 build | slower typed arrays |
| Terminal as an on-demand dylib | about 95 MB | about 38.7 MB | one, in-process code | `ghostty.h` is a C API, so it's possible, but it's in-process code from a second source |
| Terminal trimmed (no embedded fonts or shader compilers) | 101 MB | 40.2 MB | none | needs a patch on the pinned Ghostty |

**Decided (2026-10-20): ship everything in-process in the bundle, off until chosen, and take the
script runtime out of the default bundle as an on-demand component. V8 stays.** The terminal stays
in: its download cost is small, most people use it, and loading it at runtime would mean in-process
code from a second source. Trim it instead (fonts and shader compilers). The script runtime is the
exception because it's the largest single cost and already a separate, sandboxed executable:

- **Fetched only when scripting is turned on**, from the same release as the app.
- **Pinned by a SHA-256 compiled into the app**, so it can't be swapped even with the release or the
  update key compromised, and **signed and notarized like the app**; Native checks the hash, its
  Ed25519 signature and a same-team code signature before its first run, with `HostUpdater`'s
  installer and `CodeSignatureVerifier`, which already do each of these.
- **Cached per hash**, so app updates that don't bump V8 don't fetch it again.
- **Enterprise:** `policy.scripts.enabled = false` means it's never fetched;
  `policy.components.baseURL` mirrors it; MDM can pre-stage it.

JavaScriptCore would remove the download and the V8 pin entirely, but V8 was chosen on 2026-10-19
for its exact heap limit and speed, and that stands.

### Target size

With every in-process module included, measured against 2026-10-19's 107.5 MB and 42.7 MB:

| Step | Installed | Download |
| --- | --- | --- |
| Script runtime out of the bundle | -41.4 MB | -15.0 MB |
| libghostty without embedded fonts and shader compilers | -6.5 MB | -2.5 MB |
| Icons: per-channel catalogs and lossy alternates | about -3.5 MB | about -3.5 MB |
| **Target** | **under 60 MB** | **under 25 MB** |

`size-check.sh`'s budgets come down with each step (today 118 MB installed, 35 MB download; the
downloads above are ZIP measurements, and the archive has been a `.tar.xz` since 2026-10-26). The
app binary's own target is under 50 MB; the stretch, with fewer grammars, is a 20 MB download.

### Why people pick Native

- **It's theirs.** A preset on day one, then exactly the modules they want, and off really is off.
  Agents can extend it for them: the `build-a-native-plugin` skill writes plugins for agents,
  workflows, MCP servers, themes, icon sets and celebrations without rebuilding anything.
- **Every agent, one place.** Any ACP agent side by side, with one approval model, one MCP switch,
  one skill list and one policy applied across all of them, and agents that hand work to each other
  (Claude Code asking Codex for a review). Built on a protocol, so a new agent works on day one.
- **Work that doesn't stop.** Agents keep running when the app quits, and an iPad or phone can
  drive a Mac or a server.
- **Extensibility without trust.** Code plugins run in the sandboxed script runtime with only the
  tools they're granted, and contribute through the same seven places as built-in modules. A plugin
  can add a command or a workflow step without being able to read a file it wasn't given.
- **Small and calm.** A download of about 25 MB, nothing on screen it didn't ask for, nothing
  fetched it can't verify.

### Phases

Each phase ships on its own, in this order (decided 2026-10-20).

| Phase | What | Touches | Size |
| --- | --- | --- | --- |
| 0. Supply-chain fixes | Pin the V8 prebuilt's SHA-256 and pass it with `RUSTY_V8_ARCHIVE`; `-disableAutomaticPackageResolution` in CI; actions pinned by commit; Dependabot for Swift and Cargo; `rust-toolchain.toml` | `scripts/build-script-runtime.sh`, `scripts/release/`, `.github/`, `Runtime/ScriptRuntime` | small |
| 1. Plugin catalog and honest defaults | The official plugins repository, signed index, pinned commits and hashes, the install screen, update offers, catalog policy keys; non-default themes, icon sets, celebrations, workflows, experiments and extra agents move into it; built-in code features listed beside them. New installs start with Orchestration, Sounds and the status bar off; existing users' state is recorded as choices, so nothing changes for them | new `native/PluginCatalog`, a UI-free `Packages/PluginCatalog` (index, verification), `native/Plugins`, `native/Sounds`, `native/Orchestration`, `native/StatusBar`, `Packages/NativePolicy`, `scripts/release/` | medium |
| 2. Native-managed adapter installs | Each adapter installed into its own folder from a lockfile shipped in the app: exact versions with integrity hashes, `--ignore-scripts`, `--omit=optional` where the adapter doesn't need them; launched with `node <bin>`, no fresh `npx` resolution; an organization can mirror the registry | `Packages/ACP` (`NpxLaunch`), `native/Plugins`, `native/AgentCatalog`, `Packages/NativeHost` (the host launches agents), `docs/agents.md` | medium |
| 3. V8 on demand | The script runtime leaves the default bundle: fetched when scripting is turned on, SHA-256 pinned in the app, signed and notarized; budgets in `size-check.sh` come down | `Runtime/ScriptRuntime`, `Packages/ScriptRuntime`, `Packages/HostUpdater`, `scripts/release/`, `docs/app-size.md` | medium |
| 4. Modules contribute UI | `FeatureModule` and `ModuleContributions`; Settings, commands, status bar, sidebar, inspector and task rows read from the registry; the existing plugins' pages, items and sidebar entries move over and the `isEnabled` checks in `RootView` go | `native/Plugins`, `native/Settings`, `native/Commands`, `native/StatusBar`, `native/Views/RootView.swift`, `native/Wiring` | medium |
| 5. Hard-wired features become modules | One pull request each, lazily activated: Terminal, GitHub (with PR tasks and clean up), Project actions, Task scripts, Modes, Keep awake, Open in, Companion and hosts, What's New, Labs, Agent icons, Status bar | each feature's folder (`Integration/`), `native/NativeApp.swift`, `native/Wiring` | medium, parallel |
| 6. Onboarding and Extensions | The first-launch presets (Just agents, Essentials, Everything), cost badges, in-context offers | `native/Views/Home`, `native/Settings/Pages/ExtensionsSettingsPage.swift` | medium |
| 7. Enterprise module policy | The keys above, the sample profile, audit export of module and policy changes, a bill of materials published with each release | `Packages/NativePolicy`, `native/Plugins/PluginRegistry.swift`, `docs/enterprise.md`, `docs/enterprise/`, `scripts/release/` | medium |
| 8. The rest of the size | libghostty without embedded fonts and shader compilers; icon catalogs per channel | `scripts/build-libghostty.sh`, `native/Assets.xcassets`, `docs/app-size.md` | medium |
| 9. Later | Sandboxed code plugins contributing to the seven places; a signed organization plugin catalog | `Packages/ScriptRuntime`, `native/Plugins` | large |

### Decided (2026-10-20)

1. **Modules.** Modules are `NativePlugin`s that add UI to the seven existing seams, and off means
   absent. First launch offers three presets: Just agents, Essentials (the recommended default) and
   Everything. Existing users keep their current state. Policy keys cover built-in modules too.
2. **V8 stays**, and leaves the default bundle as an on-demand component: fetched only when
   scripting is turned on, pinned by a SHA-256 compiled into the app, signed and notarized like the
   app. Target: under 60 MB installed and under 25 MB to download.
3. **Native-managed adapter installs.** Native installs each agent adapter into its own folder from
   a lockfile: exact versions with integrity hashes, `--ignore-scripts`, and `--omit=optional` where
   the adapter doesn't need what it leaves out. No fresh `npx` resolution. Organizations can mirror.
4. **Order.** Phase 0, then the plugin catalog and honest defaults, then adapter installs, then V8
   on demand.
