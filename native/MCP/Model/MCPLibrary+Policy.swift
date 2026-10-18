import Foundation
import MCPClient

extension MCPLibrary {
    /// Agents' own servers switched off for this session, as intent: each agent's plugin applies it
    /// its own way (`SessionPolicyTranslator`). Native's servers that are off just aren't handed over.
    func sessionPolicy(for session: SessionContext) -> SessionPolicy {
        guard let agent = agents.first(where: { $0.id == session.agent }) else { return .none }
        let off = agentServers(agent.format, in: session.cwd).filter { entry in
            entry.status.isLoaded && mode(of: entry.server.endpoint.key, in: session.cwd) == .off
        }
        return SessionPolicy(
            disabledMCPServers: off.map { entry in
                let everywhere = switches.mode(of: entry.server.endpoint.key, in: nil) == .off
                return SessionPolicy.DisabledMCPServer(name: entry.name, scope: everywhere ? .allProjects : .session)
            })
    }

    /// Agents' own servers switched off for all projects, for agents that apply policy at launch.
    func launchPolicy(for agentID: AgentDefinition.ID) -> SessionPolicy {
        guard let agent = agents.first(where: { $0.id == agentID }), let configuration = configurations[agent.format]
        else { return .none }
        let off = configuration.servers.filter { switches.mode(of: $0.server.endpoint.key, in: nil) == .off }
        return SessionPolicy(
            disabledMCPServers: Set(off.map(\.name)).sorted().map { .init(name: $0, scope: .allProjects) })
    }
}
