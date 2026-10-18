import Foundation
import MCPClient

extension MCPLibrary {
    /// Agents' own servers, one row per server however many agents and scopes load it (the same
    /// command line or URL is the same server). With `project`, what loads there; without, every
    /// entry in every scope.
    func agentServerGroups(in project: URL?) -> [MCPAgentServerGroup] {
        let entries = agents.flatMap { agent in
            project.map { agentServers(agent.format, in: $0) } ?? configurations[agent.format]?.servers ?? []
        }
        var groups: [MCPAgentServerGroup] = []
        for entry in entries {
            if let index = groups.firstIndex(where: { $0.endpoint == entry.server.endpoint }) {
                groups[index].entries.append(entry)
            } else {
                groups.append(MCPAgentServerGroup(endpoint: entry.server.endpoint, entries: [entry]))
            }
        }
        return groups.sorted {
            ($0.isLoaded ? 0 : 1, $0.name.lowercased()) < ($1.isLoaded ? 0 : 1, $1.name.lowercased())
        }
    }

    /// The managed server with the same command line or URL, if one exists.
    func managedServer(matching endpoint: MCPEndpointIdentity) -> ManagedServer? {
        servers.first { $0.transport.endpoint == endpoint }
    }

    /// Agents that don't get a managed server from Native (outside any project) and why.
    func skippedAgents(for server: ManagedServer) -> [(agent: MCPAgent, reason: String)] {
        agents.compactMap { agent in
            let target = ManagedServerDelivery.Target(
                agentID: agent.id.rawValue, directory: nil, transports: agent.transports,
                agentServers: agentServers(agent.format, in: nil), switches: switches)
            var everywhere = server
            everywhere.projects = .all
            guard let outcome = ManagedServerDelivery.plan([everywhere], for: target).first?.outcome,
                let reason = outcome.inactiveReason(agentName: agent.name), outcome != .switchedOff
            else { return nil }
            return (agent, reason)
        }
    }

    func agent(for format: AgentConfigFormat) -> MCPAgent? {
        agents.first { $0.format == format }
    }
}

/// One server as agents load it on their own: every entry with its command line or URL.
struct MCPAgentServerGroup: Identifiable, Hashable {
    let endpoint: MCPEndpointIdentity
    var entries: [ConfiguredServer]

    var id: String {
        switch endpoint {
        case .command(let command, let arguments): ([command] + arguments).joined(separator: " ")
        case .url(let url): url
        }
    }

    /// The entry that speaks for the row: one that loads, if any.
    var primary: ConfiguredServer {
        entries.first(where: \.status.isLoaded) ?? entries[0]
    }

    var name: String { primary.name }
    var isLoaded: Bool { entries.contains(where: \.status.isLoaded) }
    var key: MCPServerKey { .agent(primary.id) }

    /// Other names agents give the same server.
    var aliases: [String] {
        Array(Set(entries.map(\.name)).subtracting([name])).sorted()
    }

    var formats: [AgentConfigFormat] {
        AgentConfigFormat.allCases.filter { format in entries.contains { $0.format == format } }
    }
}
