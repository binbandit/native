import ACP
import Foundation
import NativeHostProtocol

// What clients do to agents: list them, start, stop and restart them, sign them in, and the
// agent-level ACP calls that go through the host (listing and deleting saved sessions).
extension HostCore {
    var hostAgents: [HostAgent] {
        agentOrder.compactMap { agents[$0]?.hostAgent }
    }

    /// Starts the agent if it isn't running, and answers with how that went: a failure to start is
    /// the agent's state, not an error.
    func startAgent(_ agentID: String) async throws -> HostAgent {
        guard let link = agents[agentID] else { throw HostError.unknownAgent(agentID) }
        _ = try? await readyAgent(agentID)
        return link.hostAgent
    }

    /// Stops the agent, unless one of its sessions is working.
    func stopAgent(_ agentID: String) throws -> StopAgentResult {
        guard let link = agents[agentID] else { throw HostError.unknownAgent(agentID) }
        let isBusy = sessions.values.contains { $0.record.agentID == agentID && $0.isWorking }
        guard !isBusy, link.peer != nil else { return StopAgentResult(stopped: false, agent: link.hostAgent) }
        let generation = link.generation
        link.end()
        agentExited(agentID, generation: generation)
        return StopAgentResult(stopped: true, agent: link.hostAgent)
    }

    /// Stops the agent and starts it again on its current spec. Turns it was running recover as
    /// after a crash, telling the agent it was restarted.
    func restartAgent(_ agentID: String) async throws -> HostAgent {
        guard let link = agents[agentID] else { throw HostError.unknownAgent(agentID) }
        if link.peer != nil {
            let generation = link.generation
            link.end(cause: .agentRestarted)
            agentExited(agentID, generation: generation)
        }
        _ = try? await readyAgent(agentID)
        return link.hostAgent
    }

    /// One page of the agent's saved sessions, as the agent answered `session/list`.
    func listAgentSessions(_ params: ListAgentSessionsParams) async throws -> JSONValue {
        let link = try await readyAgent(params.agentID)
        guard let peer = link.peer else { throw HostError.agentUnavailable(link.spec.name) }
        do {
            return try await peer.request(
                "session/list", RawListSessionsRequest(cwd: params.cwd, cursor: params.cursor), as: JSONValue.self)
        } catch {
            noteAgentError(error, from: link)
            throw error
        }
    }

    /// Deletes a session from the agent's own store, closing the host session holding it.
    func deleteAgentSession(_ params: DeleteAgentSessionParams) async throws {
        let link = try await readyAgent(params.agentID)
        guard let peer = link.peer else { throw HostError.agentUnavailable(link.spec.name) }
        let identity = HostTaskIdentity(agentID: params.agentID, agentSessionID: params.agentSessionID)
        if var coordinator = coordinators.first(where: { $0.task == identity }) {
            coordinator.assignments = []
            try saveCoordinator(coordinator)
        }
        if let session = sessions.values.first(where: {
            $0.record.agentID == params.agentID && $0.record.agentSessionID == params.agentSessionID
        }) {
            await cancel(session)
            forget(session)
        }
        do {
            _ = try await peer.request(
                "session/delete", RawSessionIDRequest(sessionId: params.agentSessionID), as: JSONValue.self)
            try store.forgetClosedSessionConfig(agentID: params.agentID, agentSessionID: params.agentSessionID)
        } catch {
            noteAgentError(error, from: link)
            throw error
        }
    }

    /// Notes when an agent turned a request away until the user signs in (ACP `auth_required`).
    func noteAgentError(_ error: any Error, from link: AgentLink) {
        if (error as? RPCError)?.isAuthRequired == true, HostErrorCode(error) == nil {
            link.needsSignIn = true
        }
    }
}
