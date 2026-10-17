import Foundation

/// Decides which managed servers a session gets: the enabled ones chosen for its agent and project,
/// that the agent can connect to, and that the agent doesn't already load from its own
/// configuration (handing it a second copy would load the server twice).
public enum ManagedServerDelivery {
    public struct Target: Sendable {
        public var agentID: String
        /// The session's working directory.
        public var directory: URL?
        /// What the agent advertised; nil when it hasn't said, which is taken as HTTP-capable.
        public var transports: MCPTransportSupport?
        /// What the agent loads in `directory` from its own configuration.
        public var agentServers: [ConfiguredServer]

        public init(agentID: String, directory: URL?, transports: MCPTransportSupport?, agentServers: [ConfiguredServer]) {
            self.agentID = agentID
            self.directory = directory
            self.transports = transports
            self.agentServers = agentServers
        }
    }

    public enum Outcome: Hashable, Sendable {
        case deliver
        case disabled
        case notForAgent
        case notForProject
        case unsupportedTransport(MCPTransport.Kind)
        /// The agent loads this server itself: the same name, or the same command or URL.
        case alreadyLoaded(by: ConfiguredServer)

        public var isDelivered: Bool { self == .deliver }
    }

    public struct Decision: Hashable, Sendable, Identifiable {
        public var server: ManagedServer
        public var outcome: Outcome

        public var id: UUID { server.id }
    }

    public static func plan(_ servers: [ManagedServer], for target: Target) -> [Decision] {
        let loaded = target.agentServers.filter(\.status.isLoaded)
        return servers.map { server in
            Decision(server: server, outcome: outcome(of: server, for: target, loaded: loaded))
        }
    }

    private static func outcome(of server: ManagedServer, for target: Target, loaded: [ConfiguredServer]) -> Outcome {
        guard server.isEnabled else { return .disabled }
        guard server.agents.includes(target.agentID) else { return .notForAgent }
        guard server.includes(directory: target.directory) else { return .notForProject }
        let support = target.transports ?? MCPTransportSupport(http: true, sse: true)
        guard support.supports(server.transport.kind) else { return .unsupportedTransport(server.transport.kind) }
        let endpoint = server.transport.endpoint
        if let existing = loaded.first(where: { $0.name == server.name || $0.server.endpoint == endpoint }) {
            return .alreadyLoaded(by: existing)
        }
        return .deliver
    }
}
