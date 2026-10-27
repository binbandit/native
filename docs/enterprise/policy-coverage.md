# Policy coverage

Which managed key and which capability governs each optional part of Native, what decides it, and
the code that has to honor the decision. `Packages/NativePolicy` holds the same map in code
(`PolicyKey.role`, `PolicyKey.owners`, `PolicyCapability.coverage`), and `PolicyCoverageTests` fails
when this page, the sample profile or [enterprise.md](../enterprise.md) leaves one out.

This is schema coverage: every key and capability has a typed, managed decision with its origin and
validity. It is not enforcement coverage. A capability marked **unconverted** below has owners that
don't consult its decision yet: ordinary mode keeps today's behavior there (the key's own consumer,
where one exists), and restricted modes report it disabled whatever the policy says. That decision
only stops what consults it (plugin admission, and the registry's agents and MCP servers), plus
whatever a key's own consumer turns off with the key's restricted value. An unconverted owner
without such a switch still acts, so restricted modes aren't enforced there yet.
Converting one is a separate change per feature that makes its owners check
`NativePolicy.decision(for:)` before acting and then flips its `Enforcement` to `converted`.

## Deployment and source states

`policy.deployment.mode` is `ordinary` (the default), `internalOnly` or `airGapped`
([network admission](network-admission.md)). Internal-only and air-gapped are the restricted modes.

| Source state | When | Effect |
| --- | --- | --- |
| absent | Nothing managed, never enrolled in a restricted mode | Ordinary mode, user preferences and defaults |
| valid | Every managed value read and valid | Managed values win; restricted modes apply their rules |
| invalid | A managed value is malformed or shadowed by a launch argument, a managed configuration isn't a dictionary, the mode is unknown, or a restricted policy has keys Native doesn't know | The bad key fails closed; the last three lock everything optional down |
| unavailable | The source or its deployment mode can't be read, or a restricted policy disappeared | Everything optional denied |

Each key reports `absent`, `valid`, `invalid` or `unavailable`, and where its effective value came
from: `organization`, `user`, `default`, `restricted` (restricted mode's value) or `failClosed`.
`PolicyRevision` fingerprints the organization's input, so a report or audit record can name the
policy it applied. `NativePolicy.inspection` lists all of it without values: switches, counts, closed
options and "configured" in place of text, URLs, headers or environment.

A restricted mode the organization deploys is recorded outside preferences
(`Application Support/<bundle id>/Policy/enrollment.json`). If the profile is removed or can't be
read, Native stays in that mode with everything optional denied, across restarts. The only way out
is the organization deploying `policy.deployment.mode` = `ordinary`, which clears the record; a user
preference or a launch argument can't.

## Keys

The owner is where the key's effective value is read today. `policy.remoteHosts.enabled` and the
catalog keys have no app consumer yet; their capabilities stay off in restricted modes.

| Key | Role | Capabilities | Owner |
| --- | --- | --- | --- |
| `policy.folders.allowedRoots` | restriction | `folders.add` | `native/SidebarFolders/AppModel+SidebarFolders.swift` |
| `policy.deployment.mode` | deployment | - | `Packages/NativeNetwork/Sources/NativeNetwork/NetworkAdmission.swift` |
| `policy.network` | deployment | - | `Packages/NativeNetwork/Sources/NativeNetwork/NetworkAdmission.swift` |
| `policy.approvals.knowledge` | configuration | `approvals.knowledge` | `native/Plugins/PluginRegistry.swift` |
| `policy.approvals.countUnknownPrograms` | grant | `diagnostics.commandCoverage` | `native/CommandKnowledge/CommandKnowledgeCenter.swift` |
| `policy.agents.allowed` | grant | `agents.execution` | `native/Plugins/PluginRegistry.swift` |
| `policy.agents.environment` | configuration | `agents.execution` | `native/Plugins/PluginRegistry.swift` |
| `policy.mcp.allowed` | grant | `mcp.execution` | `native/MCP/Model/MCPLibrary+Policy.swift`, `native/Plugins/PluginRegistry.swift` |
| `policy.mcp.blocked` | restriction | `mcp.execution` | `native/MCP/Model/MCPLibrary+Policy.swift`, `native/Plugins/PluginRegistry.swift` |
| `policy.mcp.required` | grant | `agents.execution`, `mcp.execution` | `native/Policy/PolicyPlugin.swift` |
| `policy.plugins.allowed` | grant | `plugins.activation` | `native/Plugins/PluginRegistry.swift` |
| `policy.celebrations.downloadsEnabled` | grant | `celebrations.download` | `native/Celebrations/CelebrationAssetStore.swift` |
| `policy.celebrations.baseURL` | destination | `celebrations.download` | `native/Celebrations/CelebrationAssetStore.swift` |
| `policy.catalog.enabled` | grant | `plugins.catalog` | `Packages/PluginCatalog/Sources/PluginCatalog/PluginCatalogSource.swift` |
| `policy.catalog.indexURL` | destination | `plugins.catalog` | `Packages/PluginCatalog/Sources/PluginCatalog/PluginCatalogSource.swift` |
| `policy.skills.blocked` | restriction | `agents.execution`, `skills.use` | `native/Policy/PolicyPlugin.swift` |
| `policy.permissions.forbiddenModes` | restriction | `agents.execution` | `native/Policy/PolicyPermissionModes.swift` |
| `policy.scripts.enabled` | grant | `scripts.runtime` | `native/Orchestration/OrchestrationPlugin.swift` |
| `policy.git.worktreeFetch` | grant | `git.worktreeFetch` | `native/Git/Model/GitStore.swift` |
| `policy.taskScripts.userScripts` | grant | `taskScripts.user` | `Packages/TaskScripts/Sources/TaskScripts/TaskScriptPlan.swift` |
| `policy.taskScripts.repositoryScripts` | grant | `taskScripts.repository` | `Packages/TaskScripts/Sources/TaskScripts/TaskScriptPlan.swift` |
| `policy.celebrations.enabled` | grant | `celebrations.use`, `celebrations.download` | `native/Celebrations/CelebrationsPlugin.swift` |
| `policy.organization.name` | configuration | - | `native/Wiring/SessionTools/TaskWellWiring.swift` |
| `policy.organization.contact` | configuration | - | `native/Appearance/AppearancePolicyDetails.swift` |
| `policy.appearance.codeTheme` | configuration | - | `native/Appearance/AppearancePreferences.swift` |
| `policy.appearance.codeTheme.reason` | configuration | - | `native/Appearance/AppearancePolicyDetails.swift` |
| `policy.labs.enabled` | grant | `labs` | `native/Wiring/ExperimentsPolicyWiring.swift` |
| `policy.companion.enabled` | grant | `hosts.pairing` | `native/Companion/PairedDevicesSettingsPage.swift` |
| `policy.remoteHosts.enabled` | grant | `hosts.remote` | `native/Hosts/Model/RemoteHosts.swift` |
| `policy.updates.feedURL` | destination | `updates.app` | `native/Updates/UpdateState.swift` |
| `policy.updates.enabled` | grant | `updates.app`, `updates.host` | `native/Updates/UpdateState.swift` |
| `policy.updates.channels` | restriction | `updates.app`, `updates.host` | `native/Updates/UpdateState.swift` |
| `policy.search.retentionDays` | restriction | `search.index` | `native/Search/TranscriptSearchCenter.swift` |
| `policy.shortcuts.bindings` | configuration | - | `native/Commands/CommandRegistry.swift` |
| `policy.ai.instructions` | configuration | `agents.auxiliaryGeneration` | `native/AIInstructions/Model/AIInstructionsStore.swift` |
| `policy.telemetry.native` | grant | `diagnostics.native` | `native/Telemetry/TelemetryCenter.swift` |
| `policy.telemetry.endpoints` | grant | `diagnostics.organization`, `audit.export` | `native/Telemetry/TelemetryCenter.swift` |

Roles: a **grant** turns a capability on, and in a restricted mode it only takes effect for a
converted capability. A **restriction** narrows, a **destination** says where a capability connects,
**configuration** shapes behavior without allowing anything, and **deployment** picks the mode and
network envelope.

## Capabilities

Kinds keep downloads apart from local use and telemetry apart from audit. Required means the
organization makes it mandatory: `policy.telemetry.native` = `on`, a collector in
`policy.telemetry.endpoints`, or servers in `policy.mcp.required`. A required capability that
something else denies is reported as a conflict, and agent sessions are denied while the servers
they must have are. `audit.local` is the local activity record: it grants nothing, so it is always
required.

| Capability | Kind | Keys | Network services | Owners | Enforcement |
| --- | --- | --- | --- | --- | --- |
| `folders.add` | local | `policy.folders.allowedRoots` | - | `native/SidebarFolders/AppModel+SidebarFolders.swift` | converted |
| `agents.execution` | execution | `policy.agents.allowed`, `policy.agents.environment`, `policy.permissions.forbiddenModes`, `policy.skills.blocked`, `policy.mcp.required` | `agents.provider`, `agents.ipc` | `native/Plugins/PluginRegistry.swift`, `Packages/NativeHost/Sources/NativeHost/AgentLink.swift` | unconverted |
| `agents.auxiliaryGeneration` | execution | `policy.ai.instructions` | `agents.provider` | `native/Plugins/SessionTitles.swift`, `native/AIInstructions/` | unconverted |
| `agents.install` | download | - | `adapters.install`, `agents.installGuides` | `Packages/ACP/Sources/ACP/NpxLaunch.swift`, `Packages/NativeHost/Sources/NativeHost/ManagedAdapterInstaller.swift`, `native/AgentCatalog/` | unconverted |
| `agents.signIn` | execution | - | `agents.provider`, `external.open` | `native/AgentCatalog/AgentTerminalSignIn.swift` | unconverted |
| `terminal` | execution | - | - | `native/Terminal/` | unconverted |
| `mcp.execution` | execution | `policy.mcp.allowed`, `policy.mcp.blocked`, `policy.mcp.required` | `mcp.stdio`, `mcp.http`, `mcp.sse` | `native/Plugins/PluginRegistry.swift`, `native/MCP/Model/MCPLibrary+Policy.swift`, `Packages/MCPClient/` | unconverted |
| `mcp.probe` | network | - | `mcp.probe` | `Packages/MCPClient/Sources/MCPClient/Client/` | unconverted |
| `plugins.activation` | local | `policy.plugins.allowed` | - | `native/Plugins/PluginRegistry.swift` | converted |
| `plugins.appearance` | local | - | - | `native/Plugins/PluginRegistry.swift` | converted |
| `plugins.catalog` | download | `policy.catalog.enabled`, `policy.catalog.indexURL` | `catalog.index` | `Packages/PluginCatalog/` | unconverted |
| `approvals.knowledge` | local | `policy.approvals.knowledge` | - | `native/Plugins/PluginRegistry.swift` | converted |
| `skills.use` | local | `policy.skills.blocked` | - | `native/Skills/`, `native/Policy/PolicyPlugin.swift` | unconverted |
| `skills.download` | download | - | `skills.search`, `skills.download`, `skills.git` | `Packages/Skills/` | unconverted |
| `scripts.runtime` | execution | `policy.scripts.enabled` | - | `native/Orchestration/OrchestrationPlugin.swift`, `Runtime/ScriptRuntime/` | unconverted |
| `taskScripts.user` | execution | `policy.taskScripts.userScripts` | - | `native/TaskScripts/`, `Packages/TaskScripts/` | unconverted |
| `taskScripts.repository` | execution | `policy.taskScripts.repositoryScripts` | - | `native/TaskScripts/`, `Packages/TaskScripts/` | unconverted |
| `git.local` | execution | - | - | `Packages/Git/`, `native/Git/` | unconverted |
| `git.worktreeFetch` | network | `policy.git.worktreeFetch` | `git.remote` | `native/Git/Model/GitStore.swift` | unconverted |
| `git.remote` | network | - | `git.remote` | `Packages/Git/` | unconverted |
| `github` | network | - | `github.cli`, `github.avatar` | `Packages/GitHub/`, `native/GitHub/` | unconverted |
| `icons.download` | download | - | `icons.index`, `icons.assets` | `native/AgentIcons/AgentIconRegistry.swift` | converted |
| `celebrations.use` | local | `policy.celebrations.enabled` | - | `native/Celebrations/CelebrationsPlugin.swift` | unconverted |
| `celebrations.download` | download | `policy.celebrations.enabled`, `policy.celebrations.downloadsEnabled`, `policy.celebrations.baseURL` | `celebrations.index`, `celebrations.signature`, `celebrations.assets` | `native/Celebrations/CelebrationAssetStore.swift` | unconverted |
| `components.download` | download | - | `components.download` | `Packages/HostUpdater/Sources/HostUpdater/PinnedComponentCache.swift` | unconverted |
| `updates.app` | download | `policy.updates.enabled`, `policy.updates.feedURL`, `policy.updates.channels` | `updates.app.feed`, `updates.app.assets`, `updates.app.notes` | `native/Updates/` | unconverted |
| `updates.host` | download | `policy.updates.enabled`, `policy.updates.channels` | `updates.host.feed`, `updates.host.signature`, `updates.host.assets` | `Packages/HostUpdater/`, `Packages/NativeHost/Sources/NativeHostMac/MacHostUpdates.swift` | unconverted |
| `diagnostics.native` | telemetry | `policy.telemetry.native` | `diagnostics.native` | `native/Telemetry/` | unconverted |
| `diagnostics.organization` | telemetry | `policy.telemetry.endpoints` | `diagnostics.organization` | `native/Telemetry/TelemetryCenter.swift`, `Packages/Telemetry/` | unconverted |
| `diagnostics.commandCoverage` | local | `policy.approvals.countUnknownPrograms` | - | `native/CommandKnowledge/CommandKnowledgeCenter.swift` | unconverted |
| `audit.local` | audit | - | - | `Packages/NativeHost/` | unconverted |
| `audit.export` | audit | `policy.telemetry.endpoints` | `diagnostics.organization` | `Packages/Telemetry/` | unconverted |
| `hosts.local` | local | - | `hosts.localIPC` | `native/Host/`, `Packages/NativeHost/` | unconverted |
| `hosts.pairing` | network | `policy.companion.enabled` | `hosts.pair`, `hosts.listener`, `hosts.discovery` | `native/Companion/`, `Packages/NativeLink/` | unconverted |
| `hosts.remote` | network | `policy.remoteHosts.enabled` | `hosts.connect`, `hosts.discovery` | `native/Hosts/Model/RemoteHosts.swift` | unconverted |
| `external.open` | external | - | `external.open` | `native/Platform/PlatformURLOpener.swift`, `native/OpenIn/` | unconverted |
| `data.export` | external | - | - | `native/Artifacts/ArtifactViewerModel.swift`, `native/Platform/PlatformArtifactActions.swift` | unconverted |
| `search.index` | storage | `policy.search.retentionDays` | - | `native/Search/` | unconverted |
| `labs` | local | `policy.labs.enabled` | - | `native/Wiring/ExperimentsPolicyWiring.swift`, `native/Experiments/` | unconverted |
| `orchestration` | execution | - | `orchestration.loopback` | `native/Orchestration/`, `Packages/MCPServer/` | unconverted |
| `automation` | execution | - | - | `native/Automation/`, `native/Expeditions/` | unconverted |
| `sounds` | local | - | - | `native/Sounds/` | unconverted |
| `usage` | local | - | - | `native/Usage/` | unconverted |

## Plugin admission

`PluginRegistry` asks `NativePolicy.admission(ofPlugin:origin:capabilities:)` before a plugin
contributes anything, before each `prepareForLaunch` and again when it finishes, and before each
event. A plugin revoked while preparing isn't counted as prepared and contributes nothing.

- Ordinary mode keeps today's rules: `policy.plugins.allowed` covers installed plugins, and built-in
  plugins answer to their own keys.
- Restricted modes admit a plugin only when `policy.plugins.allowed` lists it, built in or installed,
  and every capability it declares is permitted. A plugin that declares nothing stays off. A
  manifest declares itself through what it contributes (agents, MCP servers, workflows, themes and
  icon sets, celebrations, experiments, command knowledge), so a built-in manifest and the same
  manifest installed from disk get the same decision. Built-in code plugins don't declare
  capabilities yet, so restricted modes keep them off; each declares its own in its conversion.
- System plugins (the organization's policy, telemetry, task scripts) are never listed, and are
  admitted by their declared capabilities. The policy plugin declares none and always applies.

## Follow-ups

- **enterprise-policy-UI**: show the effective policy, each value's origin, errors and recovery
  instructions in Settings, from `NativePolicy.inspection`. Needs the main Mac for visual checks.
- One conversion per unconverted capability above, starting with the [network admission
  backlog](network-admission.md#conversion-backlog) and the detached host's own policy.
