# Regulated environments

Audit date: 2026-10-21. Source baseline: `d2cfc5aa` on `main`. This is a source audit and an
implementation plan, not a compliance certification or a claim that an isolated deployment works
today. No runtime behavior changes with this document.

Native has useful foundations: managed preferences, an ACP boundary, a durable host, signed
updates, opt-in diagnostics and a sandboxed script helper. It cannot yet promise that an admin
can account for and stop every connection, download, process or retained copy of work. Close those
gaps in the existing plugin and host architecture before offering a regulated deployment profile.

Read with [lean core](lean-core.md), [enterprise policy](../enterprise.md),
[catalog policy](../catalog-policy.md), [durability](../durability.md),
[architecture](../architecture.md) and [accessibility](../accessibility.md). Where an older design
describes intended behavior, the source observations below take precedence for this audit.

## Requirements and trust boundary

Government, financial and defense customers have different procurement and authorization regimes.
Some need private cloud; some permit only an internal network; some permit no network at all.
Classified use needs the customer's separate system authorization. These are engineering
requirements to make those assessments possible, not a promise of FedRAMP, CMMC, a financial
regulator's approval, Section 508 conformance or FIPS validation.

1. **Administrative control.** macOS configuration profiles and iPad managed app configuration
   must lock or disable each optional feature, endpoint, executable and download. Policy is
   authoritative on the machine performing the action, including a host with no client attached.
   A client can narrow host permissions, never widen them. Report effective values and their origin.
2. **Explicit network modes.** An air-gapped mode permits no off-machine traffic, including updates, discovery
   and telemetry. An internal-network mode permits only admin-approved destinations. Declare
   outbound requests, redirects, DNS/discovery, listeners and external URL opening in one typed
   registry. Unknown destinations fail closed in restricted mode. A mirror is an explicit allowed
   destination, not an exception to the air-gap rule.
3. **Offline supply and execution.** Install, repair and update the app, host, adapters, plugins,
   skills and script runtime from a verified local bundle or an approved internal mirror. No first
   launch download, package resolution, install script or child process may surprise the admin.
   Missing approved components produce a useful unavailable state without trying a public fallback.
4. **Private model routing.** Each agent plugin declares its provider, authentication, endpoint,
   model and update capabilities. Support on-premises and private-cloud endpoints where the agent
   can enforce them. Reject unsupported restricted configurations before launch. Include auxiliary
   model calls for titles, commits, PR questions, workflows and recovery in the same rule.
5. **Diagnostics.** Telemetry and crash reporting default off in the regulated profile, are
   independently lockable from audit, and neither collect nor queue for later when disabled.
   Native-owned collectors and organization-owned collectors are separate decisions. Do not add
   prompt, path, command, tool-output or credential text to diagnostics.
6. **Audit.** Record agent lifecycle, observable tool actions, approval request and decision,
   authenticated actor/device, policy decision and version, plugin/configuration changes, updates
   and exports. Export locally and optionally to the organization's collector. Record metadata by
   default, with separately authorized content capture. Define loss, tampering, clock and offline
   behavior. An agent that omits actions from ACP cannot be presented as fully audited.
7. **Data lifecycle.** Inventory every copy; offer managed retention, legal hold, export and deletion
   across host state, search, agents' history, attachments, task artifacts, caches and backups.
   Explain exactly what deletion covers and report failures. FileVault/OS storage encryption and
   customer backup policy remain deployment controls; unlinking a file is not secure erasure.
8. **Secrets.** Native-owned credentials and private keys belong only in the Keychain on Apple
   platforms, with references in ordinary storage. No secrets in preferences, profiles, manifests,
   URLs, logs or host session records. A future supported Linux host needs an approved OS secret
   store or must refuse secret persistence in restricted mode. Third-party CLI stores need explicit
   qualification and guidance, not a claim that Native controls their internals.
9. **Cryptography.** Where a contract requires FIPS, identify the exact validated module, OS version,
   approved algorithms and operating configuration for each cryptographic purpose. CryptoKit alone
   is not evidence of validation. Disable unsupported transports/features; do not invent crypto.
10. **Release assurance.** Deliver signed/notarized artifacts, hashes, provenance, dependency and
    license inventory, and an SBOM for each release, including embedded binaries and optional
    components. An offline recipient can verify the same provenance as an online recipient.
11. **Enterprise networking.** Document and test authenticated proxies, bypass rules and custom CA
    trust for Foundation, Sparkle, Node/npm, git/gh and every supported agent. Never solve a trust
    failure by disabling certificate or hostname verification.
12. **Accessibility.** Assess Section 508's applicable software requirements, including keyboard,
    VoiceOver, focus, contrast, scaling, reduced motion, approvals, errors and iPad interaction.
    Publish an Accessibility Conformance Report (ACR) with known exceptions and revision-bound evidence.

Native runs unsandboxed agent CLIs as the user. A network wrapper inside Native cannot constrain
arbitrary descendants, git hooks, shell startup files, MCP executables or an agent's own updater.
Restricted deployment therefore combines Native's admission checks with customer-managed OS/network
egress enforcement and qualified executable versions. Policy is not a sandbox and does not protect
against a malicious administrator or every process running as the same user. Local IPC, explicitly permitted loopback services and OS
services must remain distinguished from off-machine access.

## Inventory from the code

Scope: shipping paths in `native/`, `Packages/`, `Runtime/`, `scripts/` and `Config/`, plus the
composition in `NativeHostHelper/` and the Companion pairing secret owner. Tests, previews, XML/SVG namespace URLs and holiday citation
URLs are not runtime connections. Build/release tools are separate from installed-app behavior.
Dynamic agent, plugin, repository and MCP destinations cannot be enumerated as fixed hostnames:
their configuration and executable are the boundary. Offline behavior here is inferred from
control flow; this audit did not launch agents or packet-capture a release.

### Network, downloads and machine-to-machine surfaces

| Surface and caller | Destination and control today | What happens offline |
| --- | --- | --- |
| App updates: `native/Updates/SparkleUpdateDriver.swift`, `UpdateController.swift`, `Config/Shared.xcconfig` | Sparkle reads `SUFeedURL`: stable/beta `https://github.com/binbandit/native/releases/latest/download/appcast.xml`, nightly `/releases/download/nightly/appcast.xml`; follows feed asset/release-note URLs and CDN redirects. `policy.updates.feedURL`, `.enabled`, `.channels` apply in the app. Automatic checks are enabled by the driver; system-profile sending is disabled. Archives are signature-verified. | Check/download reports a failure; installed app remains usable. No complete prestaged-update workflow. |
| Standalone host updates: `Packages/HostUpdater/Sources/HostUpdater/HostUpdateSource.swift`, `Packages/NativeHost/Sources/NativeHostMac/MacHostUpdates.swift`, `NativeHost/HostCore+Updates.swift` | Embedded `NativeHostFeedURL` selects signed `host-feed.json` or `host-feed-beta.json`, detached `.sig`, then asset URLs. GitHub channel defaults come from `HostUpdateSource`; startup and daily checks stage new binaries. The helper to derive a feed beside an appcast exists, but the production standalone initializer reads Info.plist, not NativePolicy. | Keeps current binary and reports failure; verified staged versions and rollback ledger are local. Linux self-update is currently unavailable. |
| Crash/performance/product telemetry: `native/Telemetry/TelemetryCenter.swift`, `SentryTelemetry.swift`, `Packages/NativeDiagnostics/Sources/NativeDiagnostics/SentryPrivacy.swift` | Sentry destination comes from release-injected `NativeSentryDSN`, not a source-code hostname. Off until consent or managed `on`; managed `off` prevents startup. Debug/dev builds have no Sentry destination. Privacy reconstruction drops content, breadcrumbs, attachments and paths. | Opted-in SDK reports can be cached. Turning it off closes the SDK and removes its cache; app use continues. This is not an audit sink. |
| Organization telemetry: `Packages/Telemetry/Sources/NativeTelemetry/OTLPLogDestination.swift`, `TelemetryPipeline.swift` | HTTP(S) collector URLs, headers and attributes from `policy.telemetry.endpoints` (bare hosts get `/v1/logs`); independent of `policy.telemetry.native`. Generic policy resolution accepts user values when not managed, despite the enterprise doc describing organization-only control. No shared endpoint allowlist. | Failed sends remain in a bounded in-memory queue (default 500 records per destination); oldest records drop. Disabling a destination drops its queue. Not durable audit delivery. |
| Plugin catalog/marketplace: `Packages/PluginCatalog/Sources/PluginCatalog/`, `scripts/plugins/build-index.py`, `native/Plugins/PluginRegistry.swift`, host `PluginCatalog.swift` | Signed-index validation and publisher exist. PR #37 adds `policy.catalog.enabled` and `.indexURL` only; no shipping remote catalog fetch/install consumer was found at this baseline. Current registries load local manifests from `~/.native/plugins` and transfer manifests/assets over the host protocol. No official catalog URL is selected by the policy package. | Local plugins work. Cached remote-host assets can be read; uncached assets need the host. A future marketplace must not interpret the package inputs as already enforced. |
| Adapter acquisition: `native/Plugins/BuiltInPlugins.swift`, `PiPlugin.swift`, `Packages/ACP/Sources/ACP/NpxLaunch.swift`, host `AgentLink.swift` | `npx --yes @agentclientprotocol/claude-agent-acp@0.93.0`, `@agentclientprotocol/codex-acp@2.2.2`, `pi-acp@0.0.34`; npm registry/tarball URLs follow npm configuration, normally `registry.npmjs.org`. Only the top-level spec is pinned in the launch path; no controlled transitive install or install-script ban there. Maintainer `scripts/adapters/lockfile.py` does not replace this path. | An exact cached executable bypasses npx on supported platforms. A cache miss can attempt the registry and fail; this is not deterministic offline provisioning. |
| Agent install/sign-in guides: `native/Plugins/{BuiltInPlugins,PiPlugin,CursorPlugin,OpenCodePlugin,CopilotPlugin}.swift`, `native/AgentCatalog/` | Setup commands offer npm global installs or Homebrew (`cursor-cli`, `anomalyco/tap/opencode`, `copilot-cli`); terminal sign-in can run CLI login flows. npm/brew and the CLIs select their own download/auth endpoints. Provider documentation and key pages open externally. | Preinstalled authenticated agents can work if their provider is reachable locally. Installation/sign-in needing public services fails; no automatic internal replacement. |
| Agent/model traffic: `native/Models/AgentRuntime.swift`, `native/Models/AppModel+LaunchPolicy.swift`, host `AgentLink.swift`, `native/Plugins/*PolicyTranslator.swift` | Native uses ACP stdio; agents own API, OAuth, model-list, telemetry and self-update traffic. Includes Claude Code, Codex, Pi, Cursor, OpenCode, Copilot and arbitrary manifest commands. `policy.agents.environment` can route some providers; it is not a universal endpoint lock. Generated Git/PR text and automated tasks also use these agents. Foundation Models titles run on-device through `Packages/SessionTitling`; model availability is OS-owned. | Depends on each provider/CLI and installed assets. No model-wide offline guarantee. Unavailable on-device titles fall back through the title pipeline. No assumed public-model fallback is acceptable for the future restricted profile. |
| External MCP: `Packages/MCPClient/Sources/MCPClient/Client/{HTTPTransport,MCPProbe,MCPSession}.swift`, `native/MCP/Model/` | Configured HTTP/SSE URLs and headers, including health probes; stdio servers can make arbitrary requests. Agent-owned MCP config is also read and translated. Allow/block/required rules use names/command patterns, not a complete destination policy. | Remote probes/tools fail and report health errors. Local stdio tools can work. A local executable is not necessarily offline. |
| Native orchestration MCP: `Packages/MCPServer/Sources/MCP/MCPHTTPServer.swift`, `native/Orchestration/OrchestrationPlugin.swift`, host `HostTasks.swift` | Loopback `http://127.0.0.1:<port>/mcp/<token>`, HMAC-scoped session tokens, Origin/Host checks. Exposes task and script/tool calls to agents; those calls can reach other boundaries. App- or host-owned according to host feature settings. | Local transport works without internet; delegated agents/tools still depend on their own connections. Not a public endpoint. |
| Skills: `Packages/Skills/Sources/Skills/Registry/SkillsRegistry.swift`, `Install/SkillStage.swift`, `SkillInstallSource.swift` | `https://skills.sh/api/search?q=...&limit=...` sends search text; `/api/download/<owner>/<repo>/<skill>` fetches files. Git installs clone a supplied URL/ref; owner/repo shorthand becomes `https://github.com/<owner>/<repo>.git`. Registry base is injectable in the library, not a managed app endpoint. | Registry reports offline; git staging fails visibly; local-folder installation and installed skills remain available. |
| Agent icons: `native/AgentIcons/AgentIconRegistry.swift` | `https://cdn.agentclientprotocol.com/registry/v1/latest/registry.json`, followed by each returned icon URL. Index cache is daily and icon refresh weekly. No managed network switch. | Cached SVG, installed app icon or monogram; fetch errors retain the fallback. Background refresh still attempts a connection. |
| Celebration assets: `native/Celebrations/CelebrationAssetStore.swift` | GitHub latest-release download base from `NativeGitHubRepository`, `celebration-assets.json`, its `.sig` and indexed pack files; source override exists for development, not a full managed mirror policy. Ed25519 index verification and pack hashes. | Bundled/cached artwork works; base icon stays and chooser explains missing assets. |
| Git/GitHub: `Packages/Git/Sources/Git/Git.swift`, `Packages/GitHub/Sources/GitHub/GitHubCLI.swift`, `native/GitHub/`, `native/PullRequestTasks/` | `git` follows configured HTTPS/SSH remotes, credentials, hooks, filters and helpers; `gh` follows repo host/CLI configuration, including enterprise hosts. PR polling, review, comment, merge, clone/fetch/push and PR context acquisition cross the boundary. No common Native network admission check. | Local git works subject to hooks/helpers. Remote operations report command/network errors; cached UI is not proof of a successful refresh or mutation. |
| Droid pairing/remote hosts: `Packages/NativeLink/Sources/NativeLink/{Host,Network,Pairing,Device}/`, `NativeHostHelper/main.swift` | TCP preferred port 47118 (can move), Bonjour `_native-link._tcp`, advertised LAN/tailnet addresses, DNS lookup, Noise-authenticated paired transport. `LinkSSHPairing` runs SSH to a user destination to invoke the remote pair helper; Tailscale approval URLs can come from SSH output, not a Native relay. No shipping public relay endpoint found. Per-device grants gate methods. | LAN can work without internet. Unreachable hosts reconnect and show offline; pairing/auth requiring a remote service cannot finish. `LinkGateway.setAllowedByPolicy` exists, but no production caller was found; the default is allowed. UI companion policy is not proof that a persisted gateway shuts down. |
| External open/share surfaces: `native/Platform/PlatformURLOpener.swift`, `native/OpenIn/`, `native/Help/HelpCommands.swift`, transcript attachment views | User-selected links, agent auth links, release notes, GitHub pages and `https://agentclientprotocol.com` open via OS handlers. Files can open in editors, Finder/Quick Look or be exported/copied. These hand data to another process even without URLSession. | Local handlers/files may work; remote browsing does not. No general managed external-open/DLP policy. |

### Build and release network activity

These run on a builder, not at customer app startup. An air-gapped build needs a separately
provisioned toolchain/cache; an air-gapped install should need neither a compiler nor a registry.

| Caller | Boundary, persistence and offline behavior |
| --- | --- |
| SwiftPM package manifests and `native.xcodeproj` | GitHub sources/binary assets for Sparkle, Sentry, SwiftTreeSitter/tree-sitter and grammars, with resolved revisions. Builder writes SourcePackages/DerivedData and SwiftPM caches. Cold resolution needs sources/assets; cached exact resolution can work offline. Capture transitive binary origins in the release SBOM. |
| `scripts/build-script-runtime.sh`, `Runtime/ScriptRuntime/{Cargo.lock,rust-toolchain.toml}` | Rust toolchain acquisition through rustup when missing; Cargo/crates registry downloads; `github.com/denoland/rusty_v8/releases/download/v150.4.0/...a.gz`. Archive and linked library SHA-256 are now pinned and checked. This fixes lean-core's older unverified-V8 finding. Cache is `~/Library/Caches/Native/ScriptRuntime` unless overridden. Missing inputs fail, or disable scripting with a warning in optional builds. |
| `Runtime/ScriptRuntime/scripts/build-v8-sandbox.py` | Optional source build fetches `static.crates.io/crates/v8/...`, pinned ICU data and Rust archive from `chromium.googlesource.com`; further V8 build inputs follow that toolchain. Prestage them for offline source builds. Installed helper is currently embedded, sandboxed and jitless; the on-demand runtime in lean-core is a plan, not a present download path. `Packages/HostUpdater/.../PinnedComponent.swift` alone is not a downloader. |
| `scripts/build-libghostty.sh` | Downloads SHA-256-pinned Zig from `ziglang.org/download/...`, fetches a pinned `github.com/ghostty-org/ghostty` commit, resolves hashed Zig dependencies and uses Xcode/Metal tooling. Toolchain/source/output caches under `~/Library/Caches/native-build/{zig,ghostty,libghostty}`. Cold offline build cannot acquire missing inputs; optional builds can omit terminal support. |
| `scripts/adapters/lockfile.py`, `scripts/plugins/build-index.py` | Maintainer-only lockfile generation contacts an explicit HTTPS npm registry (default public npm), suppresses scripts/audit/funding and audits the result. Index publication signs local inputs. Neither installs a catalog plugin at app runtime. |
| `scripts/release/{release,host,celebration-assets,sentry}.sh` and signing helpers | GitHub releases/feed assets via `gh`, Apple signing/notarization services via release tools, Sentry symbol upload via CLI. Sentry CLI itself comes from a hash-pinned GitHub asset unless supplied; upload host is CLI/config-owned, and `--no-sources` excludes source bundles. Outputs include archives, DMGs, feeds, signatures and dSYMs. Credentials come from environment/temporary signing keychains or the release operator's Keychain. Publication needs connectivity; locally supplied signed artifacts need an offline verification workflow. |
| `scripts/dev/`, `scripts/ci/`, `scripts/host/`, `scripts/companion/` | Build/test/install/SSH helpers invoke system tools and write build, fixture and staging artifacts. Companion publishing reaches Apple via its dedicated release tooling. These are operator workflows, not app telemetry; no signing, publishing, credential or TestFlight changes are proposed in this audit PR. |

### Process creation

This enumerates Native's launch families and their owners. Commands supplied by plugins, agents,
repositories or a user are open-ended; their full descendant tree is not statically enumerable.

| Owner/source | Processes or dispatch | Policy/offline implications |
| --- | --- | --- |
| `native/Host/HostRegistration.swift`, `Packages/NativeHost/Sources/NativeHostClient/AttachedHost.swift` | launchd/SMAppService starts embedded Native Host; fallback starts it directly. Development registration uses launchctl. | Host survives client exit and can recover agents after restart. Must load policy before recovery, not wait for app UI. |
| `Packages/NativeHost/Sources/UserShell/LoginShell.swift` | User's login shell to collect environment. | Startup files can execute programs/network calls. Restricted launches need an explicit environment source; filtering after the shell ran is too late. |
| `Packages/ACP/Sources/ACP/AgentProcess.swift`, host `AgentLink.swift` | `/usr/bin/env` launcher, adapter/node/npx or direct CLI; agent sign-in and descendants. | Agent groups are tracked/terminated, but that is lifecycle cleanup, not executable authorization or egress confinement. |
| `Packages/Exec/Sources/Exec/LocalCommandRunner.swift`, host `HostCore+Exec.swift` | General command execution, including git, gh, SSH, helper commands and any granted client command. | Shared place for host admission/audit; app-local callers and descendants must be covered too. Remote exec journals before running, but logs command text. |
| `Packages/MCPClient/Sources/MCPClient/Host/StdioLauncher.swift` | Configured MCP commands and health-probe processes; agent CLI configuration operations. | A probe can execute an arbitrary configured program. Denied servers must not even be probed. |
| `native/Terminal/Engine/`, `native/AgentCatalog/AgentTerminalSignIn*.swift` | libghostty spawns login/custom shells, terminal jobs and sign-in scripts. | User commands and shell profiles can spawn/download anything; requires a module gate and qualified execution policy. |
| `Packages/TaskScripts/Sources/TaskScripts/TaskScript.swift`, `Packages/ProjectActions/Sources/ProjectActions/ProjectActionLaunch.swift` | Shell or shebang interpreter for user/project/repository task hooks and actions; npm/brew/build tools when requested. | Existing task-script policy and repository trust cover parts of this. Offline is entirely command-dependent. |
| `Packages/ScriptRuntime/Sources/ScriptRuntime/ScriptProcessTransport.swift` | Embedded `native-script-runtime` Rust/V8 helper. | App Sandbox has no network entitlement or general file access; bound tool calls still cross through Native and need their own policy. Missing helper makes scripting unavailable. |
| NativeLink `LinkSSHPairing.swift`, host `HostDoctorMac*.swift` | SSH plus remote `sh`/pair helper; diagnostic `gh auth status`, tool `--version`, `launchctl print`, `defaults read`, `pmset -g`, FileVault checks. | SSH/auth checks can use network; version commands execute installed binaries. Suggested repair commands in Doctor are not necessarily executed by the checker. |
| `native/OpenIn/OpenInPlatform.swift`, `native/Platform/PlatformURLOpener.swift`, host `MacHostUpdates.swift` | OS app/URL dispatch, editor command tools, `/usr/bin/open` for update installation; Sparkle's installer/relaunch helpers. | Account for OS-mediated children and data handoff, not just `Process()` calls. |
| Build/release/development scripts | xcodebuild/swift, cargo/rustc/rustup, Zig, Python, git/gh/curl, codesign/security/notary tooling, packaging tools and test fixtures. | Operator-controlled build boundary. Runtime allowlists must not silently grant the builder's broader privileges. |

### Disk, logs and credentials

In this table, **AppSupport** is `~/Library/Application Support/<bundle id>` and **HostDir** is
`~/Library/Application Support/Native`, or `Native/Channels/<channel>`. iPad uses its container's
Application Support; portable hosts use Foundation's application-support location, normally
`$XDG_DATA_HOME/Native` or `~/.local/share/Native` on Linux. Preferences are in the app's defaults
domain. All local writes below can occur offline; loss of internet does not prevent persistence.

| Data/owner | Location and current lifecycle |
| --- | --- |
| Durable host state: `HostLocation.swift`, `HostStore.swift`, `HostStore+*.swift`, `SQLite.swift` in `Packages/NativeHost` | `HostDir/host.sqlite` plus WAL/SHM, socket and lock, in a 0700 directory. Stores agent specs, session cwd/MCP config/meta/settings, unfinished prompt/content/attachments, queue, pending approvals, activity, notifications, delegated tasks, title input and closed-session config. Request deduplication is pruned after 7 days; command activity after 30 days at startup; notifications keep newest 200. No comprehensive managed retention. SQLite is not application-encrypted. |
| Transcripts and replay: host `HostSession.swift`, `Packages/Search/Sources/Search/History/` | Full streamed host replay is in memory, not a durable transcript archive. Agent-owned histories remain on disk: Claude `~/.claude/projects/.../*.jsonl` (`CLAUDE_CONFIG_DIR` override); Codex `~/.codex/sessions/...`, session index and archived sessions (`CODEX_HOME` override). Other agents choose their own stores. Native reads/imports history; it does not own every copy or guarantee its deletion. |
| Search: `Packages/Search/Sources/Search/{SearchIndex,SearchStore,TranscriptSearchDocuments}.swift`, `native/Search/` | `AppSupport/search-index.sqlite` and SQLite sidecars contain searchable conversation text and metadata. `policy.search.retentionDays` expires index entries only, not agent history or host/workflow data. Archived history can remain outside the index. |
| App/task configuration: `native/Models/{SessionCatalog,UnsentSessions}.swift`, `native/Projects/`, `native/Plugins/SessionTitles*`, feature settings/stores | `AppSupport/session-catalog.json`; defaults hold project paths/checkouts, titles, choices, unsent-session drafts, pins, modes, scripts, instructions, plugin switches, terminal/UI state, trusted repository choices and seen-notification cursors. These are content-bearing, not merely appearance settings. Closing a tab or archiving is not erasure. |
| Automation/expeditions: `Packages/Automation/.../AutomationStorage.swift`, `Packages/Expeditions/`, app integration stores | AppSupport `goals.json`, `automations.json`, `workflow-runs.json`, `workflow-tasks.json`, `expeditions.json`, `expedition-tasks.json` (directory override supported). Objectives, prompts, outputs and task links; expedition route/reports/logbook under `~/.native/expeditions/<id>/`. No common retention/delete coordinator. |
| Git/task/PR artifacts: `native/Git/`, `Packages/Git/`, `native/GitHub/Ask/Model/`, `native/PullRequestTasks/` | Task worktrees default `~/.native/worktrees/<repo>/<slug>`; repositories retain commits, refs, reflogs and `refs/native-checkpoints/*` recovery copies. PR question context/diffs are written beneath `AppSupport/PullRequestQuestions/`; PR tasks can clone repositories. Git backups/remotes are outside local delete semantics. |
| MCP and skill configuration: `native/MCP/Model/{MCPStoreFile,MCPLibrary}.swift`, `native/Skills/Model/SkillLibrary.swift`, `Packages/Skills/` | `AppSupport/mcp-servers.json` holds server descriptors, switches and remembered script approvals; designated MCP secret fields use `KeychainSecretStore`. `AppSupport/skills.json`, installed files in selected user/project agent skill roots, temporary staging and `AppSupport/Skills Trash` for undo. Native also reads agents' config/plugin/marketplace files and can invoke their CLIs to change configuration. |
| Plugins and resource caches: `PluginRegistry.swift`, host `PluginCatalog.swift`, client `PluginAssets.swift`, icon/celebration stores | `~/.native/plugins/<plugin>/plugin.json` and assets (directory override); remote plugin assets in a caller-supplied cache with `index.json` and `blobs/<hash>`. AppSupport `AgentIcons/registry.json`, `AgentIcons/icons/*.svg`, `CelebrationAssets/`, `ProjectIcons/`. Cached manifests can contain commands/URLs; no central retention inventory. |
| Usage/telemetry/logs: `native/Usage/Core/`, `native/Telemetry/`, `Packages/Telemetry/`, host protocol `Platform.swift` | AppSupport `usage-limits.json`, `usage-activity.json`, bounded `Telemetry/sent.jsonl`; installation/consent identifiers in defaults. SDK cache is `~/Library/Caches/<bundle id>/SentryTelemetry`. Native `os.Logger` goes to unified logging; portable host logs to stderr/supervisor. Host logger marks formatted messages public. Failure strings, paths and command journal content need separate redaction review; Sentry filtering does not sanitize local logs. OS crash reports are OS-controlled. `native/Usage/System/UserNotificationPoster.swift` and expedition notifications also hand task titles/messages to Notification Center, whose presentation/history is OS-managed; these local notifications are not an APNs integration. |
| Temporary/user exports: `Packages/ACP/.../PromptAttachment+Loading.swift`, `native/Terminal/Engine/GhosttyConfigBuilder.swift`, transcript attachment/export views | Pasted images in the OS temp directory, generated Ghostty configuration/temp files and theme links under bundle-id caches; user-selected attachment/export paths and clipboard. Terminal shell history and tool output files belong to the shell/command. No single cleanup contract for all of these copies. |
| Downloads/updates | npm's `~/.npm/_npx/<hash>` and registry cache (override supported); npm/brew global installations and logs; Sparkle-managed downloads/staging; standalone `~/.native/host/versions/<build>`, active symlink and update ledger. Build caches described above are builder-only. Installed versions and rollback artifacts need explicit retention separate from conversations. |
| Agent credentials: `NativeHostMac/HostKeychain.swift`, `NativeHost/HostCore+CredentialsStore.swift` | Standard non-development macOS host locations use Keychain service `Native Host` (channel variant). Development/custom locations and portable hosts use 0600 `HostDir/credentials.json`. Agent CLI OAuth/API-key storage, gh auth, git credential helpers, SSH keys/agent and inherited environment remain third-party/OS-owned. Host credentials are injected into agent memory/environment when required. |
| Pairing secrets: `NativeLink/Identity/LinkKeyStore.swift`, `Device/*PairedHostStore.swift`, `native/Hosts/Model/RemoteHosts.swift` | Host `HostDir/Link/identity.key` is a 0600 private key; `devices.json` holds paired public identities/grants. Mac client `AppSupport/Hosts/<HostID>.json` includes a per-host private key, 0600. Keychain paired-host storage exists for device clients. Mac `RemoteHostsInstallationSecret` and Companion `installationSecret` (`Companion/NativeCompanion/Model/CompanionDevice.swift`, used by `PairingFlow.swift`) are stored in defaults. Both derive per-host installation tags; they are separate from paired transport authentication keys. File permissions are useful but do not meet Keychain-only requirements. |
| MCP/session/profile secrets: `Packages/MCPServer/.../MCPServerStore.swift`, host session persistence, `NativePolicy/PolicyLoader.swift` | MCP HMAC secret is `HostDir/MCP/token-secret` or `AppSupport/Orchestration/<channel>/token-secret`, with remembered port, 0600 in 0700 directories. Session records persist hydrated MCP URLs/headers/environment and `_meta`; storing original inputs can copy credentials out of Keychain. Policy accepts literal agent environment, required-server headers/env and telemetry headers. Profiles and preferences must use secret references in the target design. |

### Existing enterprise controls and their limits

- `Packages/NativePolicy` has **24** typed keys at this baseline. macOS uses forced defaults;
  iPad uses `com.apple.configuration.managed`. `PolicyCenter` observes changes and Settings can
  label/lock managed values. The sample profile is `docs/enterprise/native-policy.mobileconfig`.
- Controls cover agent IDs/environment, MCP patterns/required servers, plugin IDs, skills by name,
  forbidden permission modes, scripts/task scripts, Labs, pairing/remote-host UI, updates, search
  retention, shortcuts, instructions and telemetry. Catalog inputs are the two additions in
  [PR #37](https://github.com/binbandit/native/pull/37), merged 2026-10-21, explicitly without runtime
  enforcement. Plugin allowlists exempt built-ins and trust self-declared IDs, not signer/version/hash.
- `PolicyResolver` reports invalid managed values and falls through toward user/default values.
  The production platform sources suppress the user value for a forced key, so malformed forced
  booleans generally reach permissive defaults. Some collections skip invalid entries. macOS's
  source cannot enumerate all forced keys today, so unknown-key diagnostics are incomplete there.
  Restricted mode needs explicit invalid/unavailable states, not a silent grant. This deliberately
  changes the older enterprise principle that bad policy should always be ignored.
- App-side policy translations cannot prove enforcement inside every agent or detached host.
  Source inspection found no production `LinkGateway.setAllowedByPolicy` caller and no NativePolicy
  integration in standalone `MacHostUpdates`. The normal host core accepts client-provided agent
  specs and session configuration; endpoint and executable admission need an authoritative host check.
- The existing journal supports recovery and "while away", not a compliance audit. In
  `HostCore+Agents.respondPermission`, the resolved choice is appended to the in-memory session log
  and the pending approval row is removed; the function does not receive the deciding client.
  `ActivityEntry.Kind` has `approvalNeeded`, not a durable approval-decision record. Thus the claim
  in `enterprise.md` about approvals and who gave them is an intended capability, not complete today.
  `HostCore+Exec` does durably journal client name and up to 500 characters of command text before
  execution; this can capture sensitive arguments without a content-capture policy.
- Supply-chain work has already improved since lean-core: V8 archive/library hashes and Rust
  version are pinned; catalog signature/schema validation and npm lockfile tooling exist. Credit
  these foundations, but do not count package helpers as a deployed catalog, offline installer or
  SBOM. Accessibility has composer AX evidence and keyboard conventions, not an app-wide ACR.

## Gap table

Rank is implementation priority. **Critical** means the proposed restricted-mode guarantee can be
bypassed or content/secrets can cross its intended boundary. **High** blocks common procurement or
deployment requirements. **Medium** needs evidence/operational completion. These are planning
severities, not CVSS ratings or claims of an exploited vulnerability.

| Rank | Requirement | Today | Gap | Severity |
| --- | --- | --- | --- | --- |
| 1 | No unapproved outbound traffic | Many independent URLSession/SDK/CLI/OS-open paths; some per-feature gates | One declared network registry, deny-by-default mode, redirect/DNS/listener coverage and qualified child-process egress enforcement | Critical |
| 2 | MDM can lock every feature and endpoint | 24 keys; built-in plugin exemptions; invalid policy can become permissive | Complete module/capability coverage, trusted source precedence, fail-closed restricted policy and visible effective configuration | Critical |
| 3 | Policy survives UI exit and every client | App translations, paired-device grants; gateway setter and standalone updater policy not wired | Host loads and rechecks authoritative policy before recovery, launch, pairing, exec and update; revocation cancels denied work | Critical |
| 4 | No surprise downloads or children; air-gapped supply | npx runtime resolution, arbitrary manifest/MCP/shell commands; app/host signatures | Locked and verified offline component bundles, explicit executable/descendant inventory, mirror-only installs and no fallback | Critical |
| 5 | Keychain-only Native secrets | MCP/standard-host keys partly in Keychain; pairing/MCP secrets and portable credentials in files; hydrated sessions can persist secrets | Secret references throughout config/store, migration/rotation, locked-Keychain behavior and qualified external CLI storage | Critical |
| 6 | Durable, attributable audit with export | Recovery journal and command text; approval choices only in live replay | Stable action/decision schema, trusted actor, outcomes, tamper evidence, local export and reliable optional collector delivery | High |
| 7 | Retention, deletion and legal hold | Search-only managed retention; scattered files/SQLite/agent stores and recovery copies | Unified data inventory and lifecycle, per-store deletion adapters, hold rules, WAL/backups/temp handling and verifiable results | High |
| 8 | Private model endpoints, proxy and CA support | Agent environment/config, gh enterprise hosts and OS defaults | Typed plugin routing capabilities, enforced endpoint profiles, no public fallback, a tested proxy/custom-CA matrix across subprocesses | High |
| 9 | FIPS-capable crypto when required | CryptoKit primitives, Noise Curve25519/ChaChaPoly/SHA-256; Ed25519 signatures and HMAC tokens | Validated-module/OS evidence and supported algorithm mode per purpose; disable incompatible features without weakening verification | High |
| 10 | Signed releases with SBOM and offline provenance | Signing/notarization, pinned inputs and signed update/assets machinery | Per-release machine-readable SBOM covering transitive and binary inputs, provenance, offline verification and update/rollback policy | High |
| 11 | Diagnostics off and lockable | Native Sentry off by consent/policy; OTLP independent; bounded queues and cache removal | One strict profile disables both destinations before startup; endpoint admission, cancellation and cache-revocation evidence across relaunches | High |
| 12 | Section 508 accessibility | Design-system adapters, keyboard map and composer AX contract | Whole-app assessment on Mac/iPad, fixes by flow and an ACR with exceptions and evidence | High |
| 13 | Trustworthy plugin/skill identity | Signed catalog parser; local IDs and skills by name | Verified install receipts, signer/hash/version policy at activation, source restrictions and consistent host/client revocation | High |
| 14 | Pairing and local IPC administration | Same-uid/same-team socket checks, Noise pins and device grants | Managed listener/discovery policy, host allowlists, explicit remote file/exec permissions, key lifecycle and gateway startup enforcement | High |
| 15 | No content in routine logs | Sentry sanitized; command journal and public formatted host logs can carry text | Typed redacted logging, separately authorized audit content and documented OS/CLI log boundaries | High |

## Phased plan

Use `NativePlugin`/lean-core modules for optional behavior, `NativePolicy` for decisions, and the
host/`Packages/Exec` boundary for execution. The core owns policy, secret references, audit admission
and shared network services; it must not add another plugin system or a giant enterprise feature
with its own bypasses. New libraries below are first-party packages, not third-party dependencies.
Existing unrestricted behavior remains the default while the restricted profile is incomplete.
Each numbered item is a separate PR with focused tests. Paths marked **new** are proposed.
Dependent items may land behind the existing opt-in mechanism, but do not advertise restricted
mode until the final acceptance gate passes.

### Phase A: policy before side effects

| PR-sized item | Files/packages touched | Completion evidence |
| --- | --- | --- |
| A1. Define restricted deployment policy, valid/invalid/absent states, provenance and precedence | `Packages/NativePolicy/Sources/NativePolicy/{PolicyKey,NativePolicy,PolicyLoader,PolicySource}.swift`, package tests, `docs/enterprise.md`, sample profile | Malformed, partial, unavailable and revoked managed configuration cannot broaden restricted access; preserve ordinary-mode compatibility. Distinguish true air gap from internal allowlist. |
| A2. Load authoritative policy in host before services/recovery | `Packages/NativeHost/Sources/NativeHost/{HostCore,HostCore+Clients}.swift`, `NativeHostMac/MacHost.swift`, `NativeHostHelper/main.swift`, **new** host policy adapter | Headless startup and forged/older client tests; host domain mapping is explicit, clients cannot relax host restrictions. Do not replay cached permissive policy after managed input fails. |
| A3. Wire companion gateway policy at startup and on change | `NativeHostHelper/main.swift`, `Packages/NativeLink/Sources/NativeLink/Host/LinkGateway.swift`, `native/Companion/`, package tests | Existing pairings plus no app: denied profile opens no TCP/Bonjour listener; runtime revocation closes channels and blocks pair CLI. Depends on A2. |
| A4. Wire standalone host update disable/mirror/channel policy | `Packages/NativeHost/Sources/NativeHostMac/MacHostUpdates.swift`, `NativeHost/HostCore+Updates.swift`, `Packages/HostUpdater/Sources/HostUpdater/HostUpdateSource.swift` | No request when disabled, no public fallback on failed mirror, and revoked policy cancels pending checks/staging. Depends on A2. |
| A5. Add module capability declarations and policy admission | `native/Plugins/{Plugin,PluginRegistry}.swift`, `Packages/NativePolicy/`, lean-core module contributions, `native/Settings/Pages/ExtensionsSettingsPage.swift` | Built-ins and installed plugins use the same allowed/required/disabled decision. Declare connections, launches, stores and secret needs. One subsequent conversion PR per feature, starting with AgentIcons, GitHub, Terminal and OpenIn; no bulk UI refactor. |
| A6. Add typed endpoint registry and injectable transport admission | **new** `Packages/NativeNetwork/`, `Packages/NativePolicy/`, unit tests | Explicit service ID, owner, destination, trigger, payload class, redirect policy and offline behavior. Block before DNS/connect; revalidate redirects and final origins; deny unknown services in restricted mode. |
| A7. Gate app-owned HTTP consumers, one consumer per PR | `native/AgentIcons/AgentIconRegistry.swift`; then `native/Celebrations/CelebrationAssetStore.swift`; then `Packages/Skills/.../SkillsRegistry.swift`; each uses A6 | Fake transport observes zero calls under denial, cache miss or retry; mirror failures stay failures. Separate small PRs, not one migration of all consumers. |
| A8. Gate MCP and updates through the registry, one transport per PR | `Packages/MCPClient/.../Client/{HTTPTransport,MCPProbe,MCPSession}.swift`; separately `native/Updates/{UpdateController,SparkleUpdateDriver}.swift` and `Packages/HostUpdater/` | Cover probes, SSE reconnect, download/notes redirects and cancellation. Verify SDK delegate seams actually stop requests; use whole-feature denial where they cannot. |
| A9. Make diagnostics restrictions complete | `native/Telemetry/{TelemetryCenter,SentryTelemetry}.swift`, `Packages/Telemetry/`, `Packages/NativeDiagnostics/`, `Packages/NativePolicy/` | Managed native-off plus empty/denied organization destinations before SDK start; tests with cached reports, in-flight send, profile changes and relaunch. Audit remains a distinct capability. |

### Phase B: controlled execution and offline delivery

| PR-sized item | Files/packages touched | Completion evidence |
| --- | --- | --- |
| B1. Add host executable admission and controlled environment | `Packages/Exec/Sources/Exec/`, host `AgentLink.swift`, `HostCore+Exec.swift`, `Packages/NativeHost/Sources/UserShell/LoginShell.swift`, `Packages/NativePolicy/` | Restricted mode does not source arbitrary login profiles. Approved path/hash/version and environment references are checked before execution; inherited credentials are minimized. Cover app fallback explicitly. |
| B2. Cover remaining launchers, one family per PR | `Packages/ACP/.../AgentProcess.swift`; `Packages/MCPClient/.../Host/StdioLauncher.swift`; `native/Terminal/Engine/`; `Packages/TaskScripts/`; `native/ProjectActions/` | Each uses B1's contract before process creation, including health probes and sign-in. Verify descendant expectations; document OS enforcement for arbitrary child traffic. |
| B3. Install built-in adapters from reviewed lockfiles | `scripts/adapters/lockfile.py`, **new** bundled adapter lockfiles/first-party installer package, `native/Plugins/`, `Packages/ACP/.../NpxLaunch.swift`, host `AgentLink.swift` | Exact transitive integrity, scripts/audit/funding off, explicit registry with no foreign resolved URLs, direct verified launch. Read offline cache/installed receipt before considering network; remove runtime npx fallback in restricted mode. |
| B4. Verify and import a local adapter bundle | Installer from B3, `native/AgentCatalog/`, `Packages/NativePolicy/`, **new** offline import manifest in `docs/enterprise/` | Fresh machine with empty npm cache and blocked network can run the qualified adapter/CLI pair. Corrupt/missing/version-mismatched artifacts fail visibly; no installer subprocess until authorized. |
| B5. Connect catalog policy to fetch/install receipts | `Packages/PluginCatalog/`, **new** `native/PluginCatalog/` consumer, `native/Plugins/PluginRegistry.swift`, host `PluginCatalog.swift`, `scripts/plugins/build-index.py` | Reuse PR #37 keys and signed-index parser. Check enablement before every fetch/install/activation; local imports and mirrors verify identical content. Pin signer/hash/version and reject ID spoofing. Coordinate with lean-core catalog work. |
| B6. Apply the same trust rule to skills and plugin assets | `Packages/Skills/Sources/Skills/Install/`, `native/Skills/Model/`, `Packages/NativeHost/Sources/NativeHostClient/PluginAssets.swift`, `Packages/NativePolicy/` | Source allowlist, pinned content, explicit review, no install from disallowed branch/URL, and stale receipt revocation; local skill use works without registry. |
| B7. Require offline prestaging for an on-demand runtime | `Packages/ScriptRuntime/`, `Packages/HostUpdater/.../PinnedComponent.swift`, `Runtime/ScriptRuntime/`, component consumer introduced by lean-core | Only when the on-demand feature lands: same-release pinned hash/signature/team checks, approved source, local import, no fetch when scripting is off. Current embedded helper remains valid offline. |
| B8. Package a verified disconnected installation/update set | **new** `scripts/release/offline-bundle.py`, `Packages/HostUpdater/`, `docs/releasing.md`, **new** `docs/enterprise/offline-install.md` | Local app/host/component import and recovery tested on a fresh account with no network; signing/provenance retained, no registry resolution. Mirror URLs include all artifacts, not merely the feed. Coordinate release integration with its owner; no credential/upload changes. |
| B9. Qualify private providers and enterprise network settings | `native/Plugins/Plugin.swift`, agent-specific plugin/translators, `Packages/NativePolicy/`, **new** `docs/enterprise/agent-network-matrix.md` | One agent per follow-up PR: endpoints/models/auth, update/telemetry behavior, HTTP(S) proxy/NO_PROXY and custom CA tested against controlled local services. Unsupported controls block restricted launch. Do not put agent-name branches in core. |

### Phase C: secrets, audit and lifecycle

| PR-sized item | Files/packages touched | Completion evidence |
| --- | --- | --- |
| C1. Introduce a secret-reference contract and serialization rules | **new** first-party `Packages/NativeSecrets/`, `Packages/NativePolicy/`, `Packages/MCPClient/.../Managed/`, host credential interfaces | No literal secrets in profiles/manifests/defaults. Canary secrets never appear in serialized descriptors, errors or diagnostics; inaccessible Keychain is a blocked action, not file fallback. |
| C2. Migrate pairing private material to Keychain | `Packages/NativeLink/Sources/NativeLink/{Identity/LinkKeyStore,Device/FilePairedHostStore,Device/PairedHostStore}.swift`, `native/Hosts/Model/RemoteHosts.swift`, `Companion/NativeCompanion/Model/{CompanionDevice,PairingFlow}.swift` | Transactional migration, restart/rollback, locked Keychain and unpair rotation tests. Keep metadata in files and explicitly remove obsolete file/defaults secret copies on both clients after verified migration. |
| C3. Move MCP signing secrets and scrub hydrated session persistence | `Packages/MCPServer/.../{MCPServerStore,MCPTokenSigner}.swift`, host `HostStoreRecords.swift`, `HostStore.swift`, session creation/reload, `native/MCP/Model/` | Store references and reconstruct tokens/headers/env at launch; migrate old DB/WAL records and rotate exposed material. No loss of approved sessions; locked secret store blocks tools safely. |
| C4. Restrict file credential fallback and external auth contracts | `Packages/NativeHost/.../{HostCore+CredentialsStore,HostCore+CredentialsState}.swift`, `NativeHostMac/HostKeychain.swift`, agent plugin auth metadata | Standard/custom/headless deployments have explicit supported secret storage. Development/test stores remain isolated. Document gh/agent/SSH storage that Native cannot migrate; refuse unsupported restricted persistence. |
| C5. Persist approval decisions with trusted actors | `Packages/NativeHost/Sources/NativeHost/{HostCore+Agents,HostCore+Clients,HostCore+Notifications,HostStore}.swift`, `NativeHostProtocol/HostActivity.swift` | Request, decision, actor/device and session/action IDs survive crash/restart; response only after durable recording. Notification and direct RPC paths produce the same record; duplicate decisions remain first-wins. |
| C6. Add content-free audit event schema and local export | **new** `Packages/NativeAudit/`, host event/store integration, **new** export API in `NativeHostProtocol` and `NativeHostClient` | Versioned JSONL export, sequence/cursor/gap detection, policy revision, begin/end/failure outcomes and clock metadata. Retain zero prompt/command text by default; tools missing ACP evidence are marked unobserved. Audit append failure follows a declared restricted-mode stop policy. |
| C7. Add tamper-evident checkpoints and optional collector outbox | `Packages/NativeAudit/`, host persistence, `Packages/Telemetry/` transport seam, `Packages/NativePolicy/` | Durable bounded outbox, retry/idempotency, offline export and collector acknowledgements; admin chooses retention/backpressure rather than silent drop. Signed checkpoints/remote anchoring expose alteration; do not claim same-user files are tamper-proof. Depends on crypto review in D1. |
| C8. Remove routine content logging | host `HostCore+Exec.swift`, `NativeHostProtocol/Platform.swift`, selected error call sites in `native/` and packages | Typed categories, opaque IDs and counts by default. Separate managed audit-content permission; canary commands, tokens, paths and tool text are absent from routine logs and exports. One affected subsystem per fix PR. |
| C9. Define data-store inventory and lifecycle API | **new** `Packages/NativeDataLifecycle/`, `Packages/NativePolicy/`, **new** `docs/enterprise/data-lifecycle.md` | Each owner registers paths/schema, content class, retention, export/delete/hold semantics, backup exclusions and failures. No broad deletion of arbitrary user folders. |
| C10. Implement retention/deletion one store family per PR | Host SQLite/WAL; separately `Packages/Search/`; then `Packages/Automation/` and `Packages/Expeditions/`; then app caches/temp/PR artifacts and credential references | Inventory-backed purge with legal hold and dry-run result, crash-resumable deletion, no reindex resurrection, explicit agent-store adapter limits. Include checkpoints/reflogs, backups and remote copies in results, without promising secure SSD erasure. |

### Phase D: evidence for procurement

| PR-sized item | Files/packages touched | Completion evidence |
| --- | --- | --- |
| D1. Record crypto purposes and validated deployment choices | `docs/enterprise/` **new crypto assessment**, `Packages/NativeLink/Sources/NativeLink/Noise/`, `Packages/MCPServer/`, `Packages/HostUpdater/`, `Packages/PluginCatalog/`, `Packages/AppAppearance/` | Inventory Noise, signature verification, HMAC, hashes, RNG, Keychain and transport TLS. Map each to OS/module validation and approved mode. If the required mode cannot be demonstrated, disable that capability; a reviewed transport change is a separate PR, never weaker verification. |
| D2. Generate a release SBOM from actual shipped inputs | **new** `scripts/release/sbom.py`, SwiftPM resolved files, `Runtime/ScriptRuntime/Cargo.lock`, adapter lockfiles, existing build pin metadata, `docs/releasing.md` | SPDX or CycloneDX output covers transitive packages, Sentry/Sparkle binaries, Rust/V8, Zig/Ghostty dependencies, parsers, fonts/assets and optional artifacts; reconcile against bundle contents. Attach hashes/provenance through existing release-owner integration, with offline verification instructions. |
| D3. Document proxy/custom-CA support and close transport gaps | `Packages/NativeNetwork/`, transport-specific adapters, **new** `docs/enterprise/networking.md` | Matrix for system trust, Node trust, git/gh, npm, Sparkle, agents, auth proxies and redirect bypass. Test valid/invalid custom roots and offline DNS without disabling TLS checks. Secrets stay in C1 references. |
| D4. Run accessibility assessment, then fix one flow per PR | `docs/accessibility.md`, `docs/keyboard.md`, `native/DesignSystem/`, affected views/Previews and platform adapters | Keyboard/VoiceOver approvals, transcript, settings, install/error states and iPad touch/pointer/scaling checks; ACR records tested build/OS, applicable criteria and exceptions. Requires GUI-capable main-Mac verification, not build-Mac screenshots. |

### Phase E: deployment acceptance, not a new feature bundle

One final harness/docs PR in **new** `scripts/tests/regulated/` and `docs/enterprise/` ties the
independent controls together. Use fake agents, local servers and isolated Debug instances, with
customer OS egress policy applied in a dedicated test environment. No live user content.

- Fresh account, empty caches, network denied: offline install, launch, approved local agent/MCP,
  approval, export, restart, update and rollback succeed without DNS/public requests. Missing
  artifacts show a useful action. OS-owned traffic is measured and assigned to deployment controls.
- Internal-only allowlist: capture all app/host/descendant connections and listeners, including
  redirect, IPv4/IPv6, DNS, Bonjour, retry, health-check and external-open paths. Reject destinations
  absent from the registry and exercise an agent trying an unauthorized endpoint.
- Profile arrives late, is malformed, changes while a turn/download/send runs, or is removed:
  restricted operations stay blocked until valid authority exists. Quit the app and repeat through
  the host, paired device and local RPC. Verify that recovery cannot revive denied work.
- Keychain locked, disk full, audit sink unavailable, interrupted deletion and expired/revoked
  pairing: show actionable failures, preserve legal holds, avoid leaked secrets and account for gaps.
- Match release artifacts to SBOM/provenance, verify offline, then attach crypto and accessibility
  evidence for the exact supported OS/build. Publish the operating envelope and unsupported cases.

Only after this gate passes should deployment documentation describe Native as supporting the
restricted profile. Customer authorization, network enforcement, OS hardening, external-agent
qualification and any required independent assessment remain explicit responsibilities.
