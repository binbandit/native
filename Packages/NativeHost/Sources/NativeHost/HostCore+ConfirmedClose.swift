import ACP
import NativeHostProtocol

extension HostCore {
    /// Cleanup of owned files needs an acknowledgement, not the ordinary best-effort close.
    /// Process snapshots cannot establish that detached commands exited, so only the agent's
    /// explicit acknowledgement permits releasing files. Durable receipt owners retain their identity.
    func closeSessionConfirmed(_ id: HostSessionID) async throws {
        let session = try session(id)
        guard !participatesInCoordination(session, retainingSettledReceipts: false), !session.holdsRestart,
            !session.isStopping,
            session.queue.isEmpty
        else {
            throw HostError.busy("Wait for this task and its agents to finish, then retry. Its private files are kept.")
        }
        guard let link = agents[session.record.agentID] else {
            throw HostError.busy("Couldn't confirm that this task closed. Its private files are kept.")
        }
        let generation = link.generation
        guard link.capabilities?.closeSessions == true, let peer = link.peer,
            let agentSessionID = session.record.agentSessionID
        else {
            throw HostError.busy(
                "This agent can't confirm closing this task. Open it and retry. Its private files are kept.")
        }
        // needsLoad can also mean a best-effort idle unload, whose close may have failed.
        _ = try await peer.request(
            "session/close", RawSessionIDRequest(sessionId: agentSessionID), as: JSONValue.self)
        // Another client may have resumed or replaced it while the agent answered.
        guard sessions[id] === session, agents[session.record.agentID] === link, link.generation == generation,
            !participatesInCoordination(session, retainingSettledReceipts: false),
            !session.holdsRestart, !session.isStopping, session.queue.isEmpty
        else {
            throw HostError.busy("The task changed while closing. Retry when it's ready. Its private files are kept.")
        }
        try store.keepClosedSessionConfig(session.record)
        if participatesInCoordination(session) {
            unload(session, closingWith: nil)
        } else {
            forget(session)
        }
    }
}
