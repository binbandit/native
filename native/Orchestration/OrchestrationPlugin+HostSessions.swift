import ACP
import Foundation
import NativeHostClient
import NativeHostProtocol
import NativePolicy
import Observation
import os

// Sessions in Native's host keep the MCP servers they were first given and hand them to the agent at
// every reload. Most launches give them nothing new: the server's port and their tokens last. When
// they don't (sessions from before they lasted, or a move off a taken port), this gives the host
// each session's current URL, so the next reload brings the tools back.
extension OrchestrationPlugin {
    /// Once the server listens and the host is connected, hands every session the host runs this
    /// launch's URL for its next `session/load`. Sessions loaded right now keep the address they
    /// have; after a move, the status says so.
    func refreshURLs(in durableHost: DurableHost, plugins: PluginRegistry) async {
        let status = status
        let ready = Observations {
            guard case .connected = durableHost.connection else { return false }
            return status.launch != nil
        }
        for await isReady in ready where isReady {
            break
        }
        // Only for sessions that get the server at all: adding it to a stored list mustn't get past
        // the plugin's switch or the organization's policy.
        guard plugins.isEnabled(Self.id), PolicyCenter.shared.policy.mcp.allows(name: Self.serverName),
            let client = durableHost.client
        else { return }
        let sessions: [HostSessionSummary]
        do {
            sessions = try await client.sessions().filter { $0.origin != .announced }
        } catch {
            Self.logger.error("Couldn't list the host's sessions: \(error.localizedDescription, privacy: .public)")
            return
        }
        var refreshed = 0
        for session in sessions {
            guard let url = url(for: session.id.rawValue),
                let server = try? JSONDecoder().decode(
                    JSONValue.self, from: JSONEncoder().encode(MCPServer.http(name: Self.serverName, url: url)))
            else { continue }
            do {
                try await client.setMCPServers(
                    SetMCPServersParams(sessionID: session.id, mcpServers: [server], replacingNamed: true))
                refreshed += 1
            } catch {
                Self.logger.error(
                    "Couldn't update a host session's MCP URL: \(error.localizedDescription, privacy: .public)")
            }
        }
        if refreshed > 0 {
            status.leftSessionsBehind()
        }
    }
}
