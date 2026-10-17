import ACP
import Foundation

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
}

extension MCPServersPlugin {
    /// Points the library at the app: its agents, projects, shell environment and other plugins'
    /// servers, and Claude Code's `/context` reports (from the Usage feature) for context costs.
    static func connect(to model: AppModel, contextReports: @escaping @MainActor () -> [SessionKey: ContextReport]) {
        guard let library = library(in: model.plugins) else { return }
        library.host = AppMCPHost(model: model, contextReports: contextReports)
        Task { await library.readConfigurations() }
    }

    static func library(in registry: PluginRegistry) -> MCPLibrary? {
        registry.plugins.lazy.compactMap { ($0.plugin as? MCPServersPlugin)?.library }.first
    }
}
