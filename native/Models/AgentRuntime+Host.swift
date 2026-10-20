import ACP
import Foundation
import NativeHostClient
import NativeHostProtocol

// An agent running in Native's host (`HostSessions`): the host starts and stops its process, and
// says how it's doing with `_native/agents/changed`, which `AppModel` hands to `apply(_:)`.
extension AgentRuntime {
    /// Asks the host to start the agent and waits until it's ready or has failed.
    func startOnHost() async {
        guard let host else { return }
        do {
            apply(try await host.startAgent(agent.id.rawValue))
        } catch {
            apply(
                HostAgent(
                    id: agent.id.rawValue, name: agent.displayName, state: .failed,
                    problem: error.localizedDescription))
        }
    }

    /// Asks the host to stop the agent, to give its memory back. The host refuses while any of its
    /// sessions is working; returns whether it stopped.
    func parkOnHost() async -> Bool {
        guard let host, isReady else { return false }
        guard let result = try? await host.stopAgent(agent.id.rawValue) else { return false }
        apply(result.agent)
        return result.stopped
    }
}

/// An agent's requests outside its sessions' turns, made through Native's host: listing and
/// deleting its saved sessions. Errors the agent returns come through as they are; the host saying
/// the agent isn't running reads as the agent having gone away, as it does in the app.
struct HostAgentConnection: AgentConnection {
    let client: NativeHostClient
    let agent: AgentDefinition.ID

    enum Failure: LocalizedError {
        case unsupported(String)

        var errorDescription: String? {
            switch self {
            case .unsupported(let method): "Native's host doesn't pass \(method) on to agents."
            }
        }
    }

    func send<Request: ACPRequest>(_ request: Request) async throws -> Request.Response {
        do {
            let response: Any =
                switch request {
                case let list as ListSessionsRequest:
                    try await client.listAgentSessions(
                        ListAgentSessionsParams(agentID: agent.rawValue, cwd: list.cwd, cursor: list.cursor))
                case let delete as DeleteSessionRequest:
                    try await deleted(delete.sessionId)
                default:
                    throw Failure.unsupported(Request.method)
                }
            guard let response = response as? Request.Response else { throw Failure.unsupported(Request.method) }
            return response
        } catch let error where HostErrorCode(error) == .agentUnavailable {
            throw ACPConnectionError.disconnected
        } catch NativeHostClient.Failure.notConnected {
            throw ACPConnectionError.disconnected
        }
    }

    private func deleted(_ session: SessionID) async throws -> EmptyResponse {
        try await client.deleteAgentSession(DeleteAgentSessionParams(agentID: agent.rawValue, agentSessionID: session))
        return try JSONDecoder().decode(EmptyResponse.self, from: Data("{}".utf8))
    }
}
