import Foundation
import MCPClient

extension MCPLibrary {
    /// Agents' own servers switched off for this session, or reached through Native's scripts
    /// instead, as intent: each agent's plugin applies it its own way (`SessionPolicyTranslator`).
    /// Native's own servers in those modes just aren't handed over.
    func sessionPolicy(for session: SessionContext) -> SessionPolicy {
        guard let agent = agents.first(where: { $0.id == session.agent }) else { return .none }
        let off = agentServers(agent.format, in: session.cwd).filter { entry in
            entry.status.isLoaded && !mode(of: entry.server.endpoint.key, in: session.cwd).reachesAgents
        }
        return SessionPolicy(
            disabledMCPServers: off.map { entry in
                let everywhere = !switches.mode(of: entry.server.endpoint.key, in: nil).reachesAgents
                return SessionPolicy.DisabledMCPServer(name: entry.name, scope: everywhere ? .allProjects : .session)
            })
    }

    /// Agents' own servers kept from every project, for agents that apply policy at launch.
    func launchPolicy(for agentID: AgentDefinition.ID) -> SessionPolicy {
        guard let agent = agents.first(where: { $0.id == agentID }), let configuration = configurations[agent.format]
        else { return .none }
        let off = configuration.servers.filter { !switches.mode(of: $0.server.endpoint.key, in: nil).reachesAgents }
        return SessionPolicy(
            disabledMCPServers: Set(off.map(\.name)).sorted().map { .init(name: $0, scope: .allProjects) })
    }
}
