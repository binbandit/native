import ACP
import Foundation

#if canImport(AppKit)
import AppKit
#endif

/// Delivers the MCP servers configured in Native to every session: once in Settings ▸ MCP Servers,
/// every agent (or the ones chosen) gets them in every project (or the ones chosen). Agents that
/// already load a server from their own configuration don't get a second copy, and agents that
/// can't use a transport don't get servers that need it.
struct MCPServersPlugin: NativePlugin {
    static let id = "mcp-servers"

    let manifest = PluginManifest(
        id: Self.id,
        name: "MCP Servers",
        description:
            "Gives every agent the MCP servers you set up in Native, and shows the servers each agent loads on its own."
    )

    /// One for the app: the settings page, the session list and this plugin read the same servers.
    let library = MCPLibrary()

    func mcpServers(for session: SessionContext) -> [MCPServer] {
        library.mcpServers(for: session)
    }

    func sessionPolicy(for session: SessionContext) -> SessionPolicy {
        library.sessionPolicy(for: session)
    }

    func launchPolicy(for agent: AgentDefinition.ID) -> SessionPolicy {
        library.launchPolicy(for: agent)
    }

    /// Agents that apply switches at launch need agents' own configuration read first.
    func prepareForLaunch() async {
        await library.configurationsRead()
    }

    /// A turn ending may leave an agent idle with a launch policy to pick up.
    func handle(_ event: SessionEvent) async {
        if case .turnEnded = event {
            await library.host?.mcpApplyLaunchPolicies(force: false)
        }
    }
}

extension MCPServersPlugin {
    /// Points the library at the app: its agents, projects, shell environment and other plugins'
    /// servers, and Claude Code's `/context` reports (from the Usage feature) for context costs.
    static func connect(to model: AppModel, contextReports: @escaping @MainActor () -> [SessionKey: ContextReport]) {
        guard let library = library(in: model.plugins) else { return }
        library.host = AppMCPHost(model: model, contextReports: contextReports)
        // Servers set to run through scripts are bound into Native's run_script.
        if let orchestration = model.plugins.plugins.lazy.compactMap({ $0.plugin as? OrchestrationPlugin }).first {
            library.scriptsAvailable = orchestration.hasScripts
            orchestration.scriptExtensions.add(MCPScriptBindings(library: library))
        }
        // Agents launch soon after this, and those that apply switches at launch need the
        // configuration, so the first read starts now; they wait for it (`prepareForLaunch`).
        library.startReadingConfigurations()
        Task {
            await library.readConfigurations()
            await library.host?.mcpApplyLaunchPolicies(force: false)
        }
        // Agents' files change outside Native; coming back to the app is when that matters.
        #if canImport(AppKit)
        _ = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main
        ) { _ in
            Task { @MainActor in await library.readConfigurationsIfStale() }
        }
        #endif
    }

    static func library(in registry: PluginRegistry) -> MCPLibrary? {
        registry.plugins.lazy.compactMap { ($0.plugin as? MCPServersPlugin)?.library }.first
    }
}
