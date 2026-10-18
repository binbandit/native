import Foundation
import MCPClient
import NativePolicy

extension MCPLibrary {
    /// What the organization's policy allows, from its keys `policy.mcp.allowed` and `.blocked`.
    var organizationPolicy: NativePolicy.MCP {
        PolicyCenter.shared.policy.mcp
    }

    /// Why the organization keeps `server` from running, for its row; nil when it may.
    func organizationLock(for server: MCPServerConfig) -> String? {
        organizationPolicy.allows(server) ? nil : "Not allowed by your organization"
    }

    /// The same for a session's server; other plugins' servers answer to `PluginRegistry`.
    func organizationLock(for entry: MCPSessionEntry) -> String? {
        switch entry {
        case .agent(let configured): organizationLock(for: configured.server)
        case .managed(let server, _): organizationLock(for: server.config(with: secrets(for: server.id)))
        case .plugin: nil
        }
    }

    /// Agents' own servers kept out of this session (switched off, reached through Native's scripts
    /// instead, or not allowed by the organization) as intent: each agent's plugin applies it its
    /// own way (`SessionPolicyTranslator`). Native's own servers in those modes just aren't handed
    /// over, and `PluginRegistry` filters what the organization blocks.
    func sessionPolicy(for session: SessionContext) -> SessionPolicy {
        guard let agent = agents.first(where: { $0.id == session.agent }) else { return .none }
        let excluded = switches.exclusions(
            of: agentServers(agent.format, in: session.cwd), in: session.cwd, policy: organizationPolicy)
        return SessionPolicy(
            disabledMCPServers: excluded.map { .init(name: $0.server.name, scope: $0.everywhere ? .allProjects : .session) })
    }

    /// Agents' own servers kept out of every project, for agents that apply policy at launch.
    func launchPolicy(for agentID: AgentDefinition.ID) -> SessionPolicy {
        guard let agent = agents.first(where: { $0.id == agentID }), let configuration = configurations[agent.format]
        else { return .none }
        let excluded = switches.exclusions(of: configuration.servers, in: nil, policy: organizationPolicy)
        return SessionPolicy(
            disabledMCPServers: Set(excluded.map(\.server.name)).sorted().map { .init(name: $0, scope: .allProjects) })
    }
}
