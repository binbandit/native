import ACP
import Foundation
import NativeHostProtocol

// Agents as the host runs them, and the agent-level ACP calls that go through it.
extension NativeHostClient {
    /// The agents clients offer, until the plugin registry moves into the host. With
    /// `refreshEnvironment`, the host reads the login shell's environment again for agents it
    /// starts from now on. `worktreesFolder` is where the Mac app on the host's machine makes task
    /// worktrees, which the host then lets clients reach.
    public func syncAgents(
        _ agents: [AgentSpec], refreshEnvironment: Bool = false, worktreesFolder: String? = nil
    ) async throws {
        let _: EmptyMessage = try await call(
            HostProtocol.Method.syncAgents,
            SyncAgentsParams(agents: agents, refreshEnvironment: refreshEnvironment, worktreesFolder: worktreesFolder))
    }

    public func agents() async throws -> [HostAgent] {
        try await call(HostProtocol.Method.listAgents, EmptyMessage())
    }

    /// Starts the agent if it isn't running, and answers once it's ready or failed to start.
    public func startAgent(_ agentID: String) async throws -> HostAgent {
        try await call(HostProtocol.Method.startAgent, AgentParams(agentID: agentID))
    }

    /// Stops the agent unless one of its sessions is working.
    public func stopAgent(_ agentID: String) async throws -> StopAgentResult {
        try await call(HostProtocol.Method.stopAgent, AgentParams(agentID: agentID))
    }

    /// Stops the agent and starts it again on its current spec. Turns it was running recover as if
    /// it had crashed.
    public func restartAgent(_ agentID: String) async throws -> HostAgent {
        try await call(HostProtocol.Method.restartAgent, AgentParams(agentID: agentID))
    }

    /// Signs the agent in with one of its `authMethods`; it may open a browser and wait for the user.
    public func authenticateAgent(_ agentID: String, methodID: String) async throws -> HostAgent {
        try await call(
            HostProtocol.Method.authenticateAgent, AuthenticateAgentParams(agentID: agentID, methodID: methodID))
    }

    /// One page of the agent's saved sessions (ACP `session/list`), starting the agent if needed.
    public func listAgentSessions(_ params: ListAgentSessionsParams) async throws -> ListSessionsResponse {
        try await call(HostProtocol.Method.listAgentSessions, params)
    }

    /// Deletes a session from the agent's store; a host session holding it closes too.
    public func deleteAgentSession(_ params: DeleteAgentSessionParams) async throws {
        let _: EmptyMessage = try await call(HostProtocol.Method.deleteAgentSession, params)
    }
}
