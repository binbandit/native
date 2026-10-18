import Foundation
import NativePolicy

/// One of an agent's own servers that Native keeps out of its sessions: switched off, reached
/// through Native's scripts instead, or not allowed by the organization's policy.
public struct AgentServerExclusion: Hashable, Sendable {
    public var server: ConfiguredServer
    /// Whether it's kept out of every project, so agents that apply exclusions only at launch can.
    public var everywhere: Bool
}

extension MCPServerSwitches {
    /// The servers among `servers` that load for the agent but stay out of its sessions in
    /// `directory`; with nil, only those kept out everywhere.
    public func exclusions(
        of servers: [ConfiguredServer], in directory: URL?, policy: NativePolicy.MCP
    ) -> [AgentServerExclusion] {
        servers.filter(\.status.isLoaded).compactMap { entry in
            let key = entry.server.endpoint.key
            let everywhere = !policy.allows(entry.server) || !mode(of: key, in: nil).reachesAgents
            guard everywhere || (directory != nil && !mode(of: key, in: directory).reachesAgents) else { return nil }
            return AgentServerExclusion(server: entry, everywhere: everywhere)
        }
    }
}

extension MCPServerConfig {
    /// The command line a policy's `command:` patterns match: the command and its arguments,
    /// space-separated, as Native's own servers give it. Nil for remote servers.
    public var policyCommandLine: String? {
        guard case .stdio(let command, let arguments, _, _) = transport else { return nil }
        return ([command] + arguments).joined(separator: " ")
    }
}

extension NativePolicy.MCP {
    /// Whether `server` may run, by its name and, for a local server, its command line.
    public func allows(_ server: MCPServerConfig) -> Bool {
        allows(name: server.name, command: server.policyCommandLine)
    }
}
