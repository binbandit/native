import Foundation
import NativePolicy

/// Runtime declarations are the source of truth, not a parallel hostname allowlist.
public struct NetworkInventory: Sendable {
    public enum Integration: Sendable { case mediated, externalProcess, awaitingIntegration }
    public enum Location: Sendable { case offMachine, local, configured }
    public enum Redirects: Sendable { case approvedOrigins, none, externalProcess }
    public enum DestinationSource: Sendable {
        case configured(String)
        case document(String)
        case local(String)
    }

    public let service: NativePolicy.NetworkService
    public let owner: String
    public let destination: DestinationSource
    public let trigger: String
    public let payload: String
    public let redirects: Redirects
    public let location: Location
    public let offline: String
    public let integration: Integration

    /// The original shipping default, overridable by the icons.index policy endpoint.
    public static let iconIndexURL = URL(string: "https://cdn.agentclientprotocol.com/registry/v1/latest/registry.json")
    public static let runtime = NativePolicy.NetworkService.allCases.map(declaration)

    public static func declaration(_ service: NativePolicy.NetworkService) -> NetworkInventory {
        typealias Entry = NetworkInventory
        switch service {
        case .appUpdateFeed, .appUpdateAssets, .appUpdateNotes:
            return Entry(
                service: service, owner: "native/Updates/SparkleUpdateDriver.swift",
                destination: .configured("SUFeedURL / policy.updates.feedURL; feed enclosure and release notes"),
                trigger: "startup, automatic or manual update check", payload: "version metadata and update bytes",
                redirects: .approvedOrigins, location: .offMachine, offline: "keep installed app; report check failure",
                integration: .awaitingIntegration)
        case .hostUpdateFeed, .hostUpdateSignature, .hostUpdateAssets:
            return Entry(
                service: service, owner: "Packages/HostUpdater/Sources/HostUpdater/HostUpdateSource.swift",
                destination: .configured("NativeHostFeedURL; detached signature and signed feed asset URLs"),
                trigger: "host startup and daily check", payload: "version metadata, signature, executable archive",
                redirects: .approvedOrigins, location: .offMachine, offline: "keep current or verified staged host",
                integration: .awaitingIntegration)
        case .nativeDiagnostics:
            return Entry(
                service: service, owner: "native/Telemetry/SentryTelemetry.swift",
                destination: .configured("NativeSentryDSN"), trigger: "consent or managed enablement",
                payload: "privacy-filtered diagnostics", redirects: .approvedOrigins, location: .offMachine,
                offline: "SDK may cache; disabling removes cache", integration: .awaitingIntegration)
        case .organizationDiagnostics:
            return Entry(
                service: service, owner: "Packages/Telemetry/Sources/NativeTelemetry/OTLPLogDestination.swift",
                destination: .configured("policy.telemetry.endpoints"), trigger: "configured telemetry batches",
                payload: "typed telemetry and configured resource attributes", redirects: .approvedOrigins,
                location: .configured, offline: "bounded queue drops oldest; disabling drops queue",
                integration: .awaitingIntegration)
        case .catalog:
            return Entry(
                service: service, owner: "Packages/PluginCatalog/Sources/PluginCatalog/",
                destination: .configured("policy.catalog.indexURL; explicit signed-index loader"),
                trigger: "explicit library load; no production marketplace", payload: "signed catalog metadata",
                redirects: .approvedOrigins, location: .configured, offline: "local manifests remain usable",
                integration: .awaitingIntegration)
        case .adapters:
            return Entry(
                service: service,
                owner:
                    "Packages/ACP/Sources/ACP/NpxLaunch.swift; Packages/NativeHost/Sources/NativeHost/ManagedAdapterInstaller.swift",
                destination: .configured("npm registry and lockfile tarballs; explicit audited installer"),
                trigger: "agent launch cache miss or explicit install",
                payload: "package names and executable packages",
                redirects: .externalProcess, location: .configured, offline: "exact cached executable may work",
                integration: .externalProcess)
        case .components:
            return Entry(
                service: service, owner: "Packages/HostUpdater/Sources/HostUpdater/PinnedComponentCache.swift",
                destination: .configured("explicit pinned component URL"),
                trigger: "explicit library cache acquisition",
                payload: "verified component bytes", redirects: .approvedOrigins, location: .configured,
                offline: "verified cache hit or failure; no production launch gate", integration: .awaitingIntegration)
        case .installGuides:
            return Entry(
                service: service, owner: "native/AgentCatalog/; native/Plugins/",
                destination: .configured("plugin setup command, documentation and login URLs"),
                trigger: "user install or sign in", payload: "package metadata and authentication flow",
                redirects: .externalProcess, location: .configured, offline: "preinstalled tools may work; setup fails",
                integration: .externalProcess)
        case .agentProvider:
            return Entry(
                service: service, owner: "Packages/NativeHost/Sources/NativeHost/AgentLink.swift",
                destination: .configured("agent CLI/provider configuration and environment"),
                trigger: "agent operation",
                payload: "prompts, code, tools, auth, model lists, agent telemetry and updates",
                redirects: .externalProcess, location: .configured, offline: "provider-specific; no offline guarantee",
                integration: .externalProcess)
        case .agentIPC, .mcpStdio, .localHost:
            return Entry(
                service: service,
                owner: service == .localHost ? "Packages/NativeHost/" : "Packages/ACP/; Packages/MCPClient/",
                destination: .local("stdio or Unix socket; descendants have separate egress"),
                trigger: "local connection",
                payload: "ACP, host or MCP content", redirects: .none, location: .local,
                offline: "local IPC works; descendants need separate enforcement", integration: .externalProcess)
        case .mcpHTTP, .mcpProbe, .mcpSSE:
            return Entry(
                service: service, owner: "Packages/MCPClient/Sources/MCPClient/Client/",
                destination: .configured("MCP server URL and headers"), trigger: "probe, tool call or SSE reconnect",
                payload: "tool arguments/results, authorization and health", redirects: .approvedOrigins,
                location: .configured, offline: "report health or tool failure", integration: .awaitingIntegration)
        case .orchestration:
            return Entry(
                service: service, owner: "Packages/MCPServer/Sources/MCP/MCPHTTPServer.swift",
                destination: .local("127.0.0.1 selected port /mcp/session token"),
                trigger: "session orchestration listener",
                payload: "scoped task and tool calls", redirects: .none, location: .local,
                offline: "local tools work; delegated actions have their own boundary",
                integration: .awaitingIntegration)
        case .skillsSearch, .skillsDownload:
            return Entry(
                service: service, owner: "Packages/Skills/Sources/Skills/Registry/SkillsRegistry.swift",
                destination: .configured("SkillsRegistry base; search/download routes"), trigger: "search or install",
                payload: "search text and skill files", redirects: .approvedOrigins, location: .configured,
                offline: "installed skills and local folder installs remain available",
                integration: .awaitingIntegration)
        case .skillsGit:
            return Entry(
                service: service, owner: "Packages/Skills/Sources/Skills/Install/SkillStage.swift",
                destination: .configured("user git URL/ref or expanded owner/repo shorthand"),
                trigger: "skill git install",
                payload: "repository and revision", redirects: .externalProcess, location: .configured,
                offline: "staging fails visibly; installed skills remain", integration: .externalProcess)
        case .iconIndex, .iconAssets:
            return Entry(
                service: service, owner: "native/AgentIcons/AgentIconRegistry.swift",
                destination: service == .iconIndex
                    ? .configured("icons.index endpoint or iconIndexURL")
                    : .document("registry agents[].icon, including cached index"),
                trigger: "cache miss; daily index / weekly icon refresh", payload: "registry metadata and SVG bytes",
                redirects: .approvedOrigins, location: .configured,
                offline: "cached/bundled art or monogram; no bypass retry",
                integration: .mediated)
        case .celebrationIndex, .celebrationSignature, .celebrationAssets:
            return Entry(
                service: service, owner: "native/Celebrations/CelebrationAssetStore.swift",
                destination: .configured(
                    "policy.celebrations.baseURL or NativeGitHubRepository release; signed index files"),
                trigger: "artwork choice or cache refresh", payload: "signed index, signature and artwork pack",
                redirects: .approvedOrigins, location: .configured,
                offline: "bundled/cache art; missing assets explained",
                integration: .awaitingIntegration)
        case .git, .github:
            return Entry(
                service: service,
                owner: "Packages/Git/Sources/Git/Git.swift; Packages/GitHub/Sources/GitHub/GitHubCLI.swift",
                destination: .configured("repository remotes, rewrites, gh host configuration, hooks and helpers"),
                trigger: "fetch/clone/push, PR polling/review/comment/merge", payload: "repository and PR content",
                redirects: .externalProcess, location: .configured,
                offline: "local git or cached UI; remote action fails",
                integration: .externalProcess)
        case .githubAvatar:
            return Entry(
                service: service, owner: "Packages/GitHub/Sources/GitHub/GitHubAvatarCache.swift",
                destination: .document("GitHub account avatar URL"), trigger: "account avatar cache miss",
                payload: "avatar image bytes", redirects: .approvedOrigins, location: .configured,
                offline: "cached avatar or placeholder", integration: .awaitingIntegration)
        case .remoteConnect, .remotePair, .remoteDiscovery, .remoteListener:
            return Entry(
                service: service, owner: "Packages/NativeLink/Sources/NativeLink/{Network,Pairing,Host}/",
                destination: .configured(
                    "paired address/port, SSH target, Bonjour multicast and selected listener interfaces"),
                trigger: "connect/reconnect, pair, discovery or listener startup",
                payload: "host discovery, pairing and encrypted session content",
                redirects: service == .remotePair ? .externalProcess : .none, location: .configured,
                offline: "LAN may work; unreachable hosts remain offline", integration: .awaitingIntegration)
        case .externalOpen:
            return Entry(
                service: service, owner: "native/Platform/PlatformURLOpener.swift; native/OpenIn/",
                destination: .configured("user/agent/auth/help/release-note link and OS handler"),
                trigger: "open or share",
                payload: "selected URL or exported content", redirects: .externalProcess, location: .configured,
                offline: "local handlers may work; remote browsing fails", integration: .externalProcess)
        }
    }
}
