/// An optional feature or action family policy decides on as a whole, so built-in and installed
/// plugins and the features behind them answer to one decision (`NativePolicy.decision(for:)`).
/// The coverage map below names the keys and network services behind each one and the code that
/// has to honor it. Policy docs list every case (docs/enterprise/policy-coverage.md).
public enum PolicyCapability: String, CaseIterable, Hashable, Codable, Sendable {
    case agentExecution = "agents.execution"
    case auxiliaryGeneration = "agents.auxiliaryGeneration"
    case agentInstall = "agents.install"
    case agentSignIn = "agents.signIn"
    case terminal = "terminal"
    case mcpExecution = "mcp.execution"
    case mcpProbe = "mcp.probe"
    case pluginActivation = "plugins.activation"
    case pluginAppearance = "plugins.appearance"
    case pluginCatalog = "plugins.catalog"
    case commandKnowledge = "approvals.knowledge"
    case skills = "skills.use"
    case skillsDownload = "skills.download"
    case scriptRuntime = "scripts.runtime"
    case userTaskScripts = "taskScripts.user"
    case repositoryTaskScripts = "taskScripts.repository"
    case gitLocal = "git.local"
    case worktreeFetch = "git.worktreeFetch"
    case gitRemote = "git.remote"
    case github = "github"
    case iconDownload = "icons.download"
    case celebrations = "celebrations.use"
    case celebrationDownload = "celebrations.download"
    case componentDownload = "components.download"
    case appUpdates = "updates.app"
    case hostUpdates = "updates.host"
    case nativeDiagnostics = "diagnostics.native"
    case organizationDiagnostics = "diagnostics.organization"
    case commandCoverage = "diagnostics.commandCoverage"
    case audit = "audit.local"
    case auditExport = "audit.export"
    case localHost = "hosts.local"
    case pairing = "hosts.pairing"
    case remoteHosts = "hosts.remote"
    case externalOpen = "external.open"
    case export = "data.export"
    case search = "search.index"
    case labs = "labs"
    case orchestration = "orchestration"
    case automation = "automation"
    case sounds = "sounds"
    case usage = "usage"
}

extension PolicyCapability {
    /// What the capability does, so downloads stay apart from local use and telemetry from audit.
    public enum Kind: String, Sendable {
        /// Runs a process, an agent or code.
        case execution
        /// Fetches bytes that are then used locally.
        case download
        /// Talks to another machine as it works.
        case network
        /// Works only with what is already on this device.
        case local
        /// Keeps a copy of the user's work.
        case storage
        /// Hands something to another app or the system.
        case external
        case telemetry
        case audit
    }

    /// Whether the owners consult the capability's decision before acting. Restricted mode only
    /// allows converted capabilities: a key alone can't make a feature available there.
    public enum Enforcement: String, Sendable {
        case converted
        case unconverted
    }

    public enum ServiceNeed: String, Sendable {
        case all
        case any
    }

    public struct Coverage: Sendable {
        public let kind: Kind
        /// The policy keys that turn it on, off or shape it.
        public let keys: [PolicyKey]
        /// The network services it uses (`NativeNetwork.NetworkInventory` describes each).
        public let services: [NativePolicy.NetworkService]
        /// Whether it needs every one of `services`, or they are alternatives (MCP's transports).
        public let servicesNeeded: ServiceNeed
        /// Where the decision has to be honored, relative to the repository root.
        public let owners: [String]
        public let enforcement: Enforcement
    }

    public var coverage: Coverage {
        typealias Service = NativePolicy.NetworkService
        func entry(
            _ kind: Kind, _ keys: [PolicyKey] = [], _ services: [Service] = [], needing: ServiceNeed = .all,
            owners: [String], _ enforcement: Enforcement = .unconverted
        ) -> Coverage {
            Coverage(
                kind: kind, keys: keys, services: services, servicesNeeded: needing, owners: owners,
                enforcement: enforcement)
        }
        return switch self {
        case .agentExecution:
            entry(
                .execution,
                [.agentsAllowed, .agentsEnvironment, .forbiddenPermissionModes, .skillsBlocked, .mcpRequired],
                [.agentProvider, .agentIPC],
                owners: [
                    "native/Plugins/PluginRegistry.swift", "Packages/NativeHost/Sources/NativeHost/AgentLink.swift",
                ])
        case .auxiliaryGeneration:
            entry(
                .execution, [.aiInstructions], [.agentProvider],
                owners: ["native/Plugins/SessionTitles.swift", "native/AIInstructions/"])
        case .agentInstall:
            entry(
                .download, [], [.adapters, .installGuides],
                owners: [
                    "Packages/ACP/Sources/ACP/NpxLaunch.swift",
                    "Packages/NativeHost/Sources/NativeHost/ManagedAdapterInstaller.swift", "native/AgentCatalog/",
                ])
        case .agentSignIn:
            entry(
                .execution, [], [.agentProvider, .externalOpen],
                owners: ["native/AgentCatalog/AgentTerminalSignIn.swift"])
        case .terminal: entry(.execution, owners: ["native/Terminal/"])
        case .mcpExecution:
            entry(
                .execution, [.mcpAllowed, .mcpBlocked, .mcpRequired], [.mcpStdio, .mcpHTTP, .mcpSSE], needing: .any,
                owners: [
                    "native/Plugins/PluginRegistry.swift", "native/MCP/Model/MCPLibrary+Policy.swift",
                    "Packages/MCPClient/",
                ])
        case .mcpProbe: entry(.network, [], [.mcpProbe], owners: ["Packages/MCPClient/Sources/MCPClient/Client/"])
        case .pluginActivation:
            entry(.local, [.pluginsAllowed], [], owners: ["native/Plugins/PluginRegistry.swift"], .converted)
        case .pluginAppearance: entry(.local, owners: ["native/Plugins/PluginRegistry.swift"], .converted)
        case .pluginCatalog:
            entry(.download, [.catalogEnabled, .catalogIndexURL], [.catalog], owners: ["Packages/PluginCatalog/"])
        case .commandKnowledge:
            entry(.local, [.commandKnowledge], [], owners: ["native/Plugins/PluginRegistry.swift"], .converted)
        case .skills:
            entry(.local, [.skillsBlocked], [], owners: ["native/Skills/", "native/Policy/PolicyPlugin.swift"])
        case .skillsDownload:
            entry(.download, [], [.skillsSearch, .skillsDownload, .skillsGit], owners: ["Packages/Skills/"])
        case .scriptRuntime:
            entry(
                .execution, [.scriptsEnabled], [],
                owners: ["native/Orchestration/OrchestrationPlugin.swift", "Runtime/ScriptRuntime/"])
        case .userTaskScripts:
            entry(.execution, [.taskScriptsUser], [], owners: ["native/TaskScripts/", "Packages/TaskScripts/"])
        case .repositoryTaskScripts:
            entry(.execution, [.taskScriptsRepository], [], owners: ["native/TaskScripts/", "Packages/TaskScripts/"])
        case .gitLocal: entry(.execution, owners: ["Packages/Git/", "native/Git/"])
        case .worktreeFetch: entry(.network, [.worktreeFetch], [.git], owners: ["native/Git/Model/GitStore.swift"])
        case .gitRemote: entry(.network, [], [.git], owners: ["Packages/Git/"])
        case .github: entry(.network, [], [.github, .githubAvatar], owners: ["Packages/GitHub/", "native/GitHub/"])
        case .iconDownload:
            entry(
                .download, [], [.iconIndex, .iconAssets], owners: ["native/AgentIcons/AgentIconRegistry.swift"],
                .converted)
        case .celebrations:
            entry(.local, [.celebrationsEnabled], [], owners: ["native/Celebrations/CelebrationsPlugin.swift"])
        case .celebrationDownload:
            entry(
                .download, [.celebrationsEnabled, .celebrationDownloadsEnabled, .celebrationAssetsBaseURL],
                [.celebrationIndex, .celebrationSignature, .celebrationAssets],
                owners: ["native/Celebrations/CelebrationAssetStore.swift"])
        case .componentDownload:
            entry(
                .download, [], [.components],
                owners: ["Packages/HostUpdater/Sources/HostUpdater/PinnedComponentCache.swift"])
        case .appUpdates:
            entry(
                .download, [.updatesEnabled, .updatesFeedURL, .updatesChannels],
                [.appUpdateFeed, .appUpdateAssets, .appUpdateNotes], owners: ["native/Updates/"])
        case .hostUpdates:
            entry(
                .download, [.updatesEnabled, .updatesChannels],
                [.hostUpdateFeed, .hostUpdateSignature, .hostUpdateAssets],
                owners: ["Packages/HostUpdater/", "Packages/NativeHost/Sources/NativeHostMac/MacHostUpdates.swift"])
        case .nativeDiagnostics:
            entry(.telemetry, [.telemetryNative], [.nativeDiagnostics], owners: ["native/Telemetry/"])
        case .organizationDiagnostics:
            entry(
                .telemetry, [.telemetryEndpoints], [.organizationDiagnostics],
                owners: ["native/Telemetry/TelemetryCenter.swift", "Packages/Telemetry/"])
        case .commandCoverage:
            entry(.local, [.unknownCommandCounts], [], owners: ["native/CommandKnowledge/CommandKnowledgeCenter.swift"])
        case .audit: entry(.audit, owners: ["Packages/NativeHost/"])
        case .auditExport:
            entry(.audit, [.telemetryEndpoints], [.organizationDiagnostics], owners: ["Packages/Telemetry/"])
        case .localHost: entry(.local, [], [.localHost], owners: ["native/Host/", "Packages/NativeHost/"])
        case .pairing:
            entry(
                .network, [.companionEnabled], [.remotePair, .remoteListener, .remoteDiscovery],
                owners: ["native/Companion/", "Packages/NativeLink/"])
        case .remoteHosts:
            entry(
                .network, [.remoteHostsEnabled], [.remoteConnect, .remoteDiscovery],
                owners: ["native/Hosts/Model/RemoteHosts.swift"])
        case .externalOpen:
            entry(
                .external, [], [.externalOpen], owners: ["native/Platform/PlatformURLOpener.swift", "native/OpenIn/"])
        case .export:
            entry(
                .external,
                owners: ["native/Artifacts/ArtifactViewerModel.swift", "native/Platform/PlatformArtifactActions.swift"])
        case .search: entry(.storage, [.searchRetentionDays], [], owners: ["native/Search/"])
        case .labs:
            entry(
                .local, [.labsEnabled], [],
                owners: ["native/Wiring/ExperimentsPolicyWiring.swift", "native/Experiments/"])
        case .orchestration:
            entry(.execution, [], [.orchestration], owners: ["native/Orchestration/", "Packages/MCPServer/"])
        case .automation: entry(.execution, owners: ["native/Automation/", "native/Expeditions/"])
        case .sounds: entry(.local, owners: ["native/Sounds/"])
        case .usage: entry(.local, owners: ["native/Usage/"])
        }
    }
}

extension PolicyKey {
    /// What a key does to the capabilities that list it.
    public enum Role: String, Sendable {
        /// Picks the deployment mode or the network envelope.
        case deployment
        /// Turns a capability on. In restricted mode it only takes effect for converted capabilities.
        case grant
        /// Where a capability connects.
        case destination
        /// Narrows what is allowed.
        case restriction
        /// Shapes behavior without allowing anything.
        case configuration
    }

    public var role: Role {
        switch self {
        case .deploymentMode, .network: .deployment
        case .unknownCommandCounts, .agentsAllowed, .mcpAllowed, .mcpRequired, .pluginsAllowed,
            .celebrationDownloadsEnabled, .catalogEnabled, .scriptsEnabled, .worktreeFetch, .taskScriptsUser,
            .taskScriptsRepository, .celebrationsEnabled, .labsEnabled, .companionEnabled, .remoteHostsEnabled,
            .updatesEnabled, .telemetryNative, .telemetryEndpoints:
            .grant
        case .celebrationAssetsBaseURL, .catalogIndexURL, .updatesFeedURL: .destination
        case .mcpBlocked, .skillsBlocked, .forbiddenPermissionModes, .searchRetentionDays, .updatesChannels:
            .restriction
        case .commandKnowledge, .agentsEnvironment, .organizationName, .organizationContact, .appearanceCodeTheme,
            .appearanceCodeThemeReason, .shortcutBindings, .aiInstructions:
            .configuration
        }
    }

    /// The capabilities that list the key.
    public var capabilities: [PolicyCapability] {
        PolicyCapability.allCases.filter { $0.coverage.keys.contains(self) }
    }

    /// Where the key's effective value is read today, relative to the repository root.
    public var owners: [String] {
        switch self {
        case .deploymentMode, .network: ["Packages/NativeNetwork/Sources/NativeNetwork/NetworkAdmission.swift"]
        case .commandKnowledge, .agentsAllowed, .agentsEnvironment, .pluginsAllowed:
            ["native/Plugins/PluginRegistry.swift"]
        case .unknownCommandCounts: ["native/CommandKnowledge/CommandKnowledgeCenter.swift"]
        case .mcpAllowed, .mcpBlocked:
            ["native/MCP/Model/MCPLibrary+Policy.swift", "native/Plugins/PluginRegistry.swift"]
        case .mcpRequired, .skillsBlocked: ["native/Policy/PolicyPlugin.swift"]
        case .celebrationDownloadsEnabled, .celebrationAssetsBaseURL:
            ["native/Celebrations/CelebrationAssetStore.swift"]
        case .catalogEnabled, .catalogIndexURL:
            ["Packages/PluginCatalog/Sources/PluginCatalog/PluginCatalogSource.swift"]
        case .forbiddenPermissionModes: ["native/Policy/PolicyPermissionModes.swift"]
        case .scriptsEnabled: ["native/Orchestration/OrchestrationPlugin.swift"]
        case .worktreeFetch: ["native/Git/Model/GitStore.swift"]
        case .taskScriptsUser, .taskScriptsRepository: ["Packages/TaskScripts/Sources/TaskScripts/TaskScriptPlan.swift"]
        case .celebrationsEnabled: ["native/Celebrations/CelebrationsPlugin.swift"]
        case .organizationName: ["native/Wiring/SessionTools/TaskWellWiring.swift"]
        case .organizationContact, .appearanceCodeThemeReason: ["native/Appearance/AppearancePolicyDetails.swift"]
        case .appearanceCodeTheme: ["native/Appearance/AppearancePreferences.swift"]
        case .labsEnabled: ["native/Wiring/ExperimentsPolicyWiring.swift"]
        case .companionEnabled: ["native/Companion/PairedDevicesSettingsPage.swift"]
        case .remoteHostsEnabled: ["native/Hosts/Model/RemoteHosts.swift"]
        case .updatesFeedURL, .updatesEnabled, .updatesChannels: ["native/Updates/UpdateState.swift"]
        case .searchRetentionDays: ["native/Search/TranscriptSearchCenter.swift"]
        case .shortcutBindings: ["native/Commands/CommandRegistry.swift"]
        case .aiInstructions: ["native/AIInstructions/Model/AIInstructionsStore.swift"]
        case .telemetryNative, .telemetryEndpoints: ["native/Telemetry/TelemetryCenter.swift"]
        }
    }

    /// A grant restricted mode can't honor yet: every capability it turns on is unconverted.
    var grantsOnlyUnconverted: Bool {
        role == .grant && capabilities.allSatisfy { $0.coverage.enforcement == .unconverted }
    }
}
