import ACP
import Foundation
import MCPClient

extension MCPLibrary {
    /// Which managed servers a session gets and why the others don't.
    func deliveries(for session: SessionContext) -> [ManagedServerDelivery.Decision] {
        let agent = agents.first { $0.id == session.agent }
        let target = ManagedServerDelivery.Target(
            agentID: session.agent.rawValue,
            directory: session.cwd,
            transports: agent?.transports,
            agentServers: agent.map { agentServers($0.format, in: session.cwd) } ?? []
        )
        return ManagedServerDelivery.plan(servers, for: target)
    }

    /// The managed servers to hand the agent in `session/new` and `session/load`.
    func mcpServers(for session: SessionContext) -> [MCPServer] {
        deliveries(for: session).filter(\.outcome.isDelivered).map { decision -> MCPServer in
            let name = decision.server.name
            switch decision.server.config(with: secrets(for: decision.server.id)).transport {
            case .stdio(let command, let arguments, let environment, _):
                return .stdio(name: name, command: command, arguments: arguments, environment: environment)
            case .http(let url, let headers), .sse(let url, let headers):
                return .http(name: name, url: url, headers: headers)
            }
        }
    }

    /// Every server a session has, from wherever it comes: the agent's own configuration,
    /// Native's managed servers and other plugins.
    func entries(for session: SessionContext) -> [MCPSessionEntry] {
        let agent = agents.first { $0.id == session.agent }
        let own = agent.map { agentServers($0.format, in: session.cwd) } ?? []
        let managed = deliveries(for: session).filter { decision in
            switch decision.outcome {
            case .notForAgent, .disabled: false
            default: true
            }
        }
        return own.map(MCPSessionEntry.agent)
            + managed.map { MCPSessionEntry.managed($0.server, $0.outcome) }
            + (host?.mcpPluginServers(for: session) ?? []).map(MCPSessionEntry.plugin)
    }
}

/// One server in a session's list.
enum MCPSessionEntry: Identifiable, Hashable {
    case agent(ConfiguredServer)
    case managed(ManagedServer, ManagedServerDelivery.Outcome)
    case plugin(MCPPluginServer)

    var id: MCPServerKey { key }

    var key: MCPServerKey {
        switch self {
        case .agent(let entry): .agent(entry.id)
        case .managed(let server, _): .managed(server.id)
        case .plugin(let server): .plugin(server.id)
        }
    }

    var name: String {
        switch self {
        case .agent(let entry): entry.name
        case .managed(let server, _): server.name
        case .plugin(let server): server.name
        }
    }

    /// Whether the agent connects to it in this session, as far as configuration goes.
    var isActive: Bool {
        switch self {
        case .agent(let entry): entry.status.isLoaded
        case .managed(_, let outcome): outcome.isDelivered
        case .plugin: true
        }
    }

    var transportKind: MCPTransport.Kind {
        switch self {
        case .agent(let entry): entry.server.transport.kind
        case .managed(let server, _): server.transport.kind
        case .plugin(let server): server.config.transport.kind
        }
    }

    /// Where it comes from, in a few words: "Claude Code · User", "Native", "Orchestration".
    var origin: String {
        switch self {
        case .agent(let entry): "\(entry.format.displayName) · \(entry.scope.displayName)"
        case .managed: "Native"
        case .plugin(let server): server.pluginName
        }
    }
}
