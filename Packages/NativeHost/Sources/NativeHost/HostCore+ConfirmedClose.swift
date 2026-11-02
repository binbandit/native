import ACP
import NativeHostProtocol

extension HostCore {
    /// Cleanup needs acknowledgements from independent delegated sessions too: a terminal result
    /// cannot establish that detached commands released their shared private files.
    func closeSessionConfirmed(_ id: HostSessionID) async throws {
        _ = try session(id)
        let family = tasks.receiptFamily(involving: id)
        // Close the requested endpoint last so a child's refusal leaves its parent available.
        let members = family.compactMap { sessions[$0] }.sorted { $0.id != id && $1.id == id }
        let closing = try members.map { session in
            guard !participatesInCoordination(session, retainingSettledReceipts: false), !session.holdsRestart,
                !session.isStopping, session.queue.isEmpty
            else {
                throw HostError.busy(
                    "Wait for this task and its agents to finish, then retry. Its private files are kept.")
            }
            guard let link = agents[session.record.agentID] else {
                throw HostError.busy("Couldn't confirm that this task closed. Its private files are kept.")
            }
            guard link.capabilities?.closeSessions == true, let peer = link.peer,
                let agentSessionID = session.record.agentSessionID
            else {
                throw HostError.busy(
                    "This agent can't confirm closing this task. Open it and retry. Its private files are kept.")
            }
            return (
                session: session, link: link, generation: link.generation, peer: peer, agentSessionID: agentSessionID,
                lastEventAt: session.lastEventAt, loadGeneration: session.loadGeneration
            )
        }
        for target in closing {
            // needsLoad can mean a best-effort unload whose close failed, so it still needs an ack.
            do {
                _ = try await target.peer.request(
                    "session/close", RawSessionIDRequest(sessionId: target.agentSessionID), as: JSONValue.self)
            } catch let error as RPCError where error.code == -32002 {
                // ACP defines an unknown or already-closed session as successful close. A prior
                // family cleanup may have closed this member before another member refused.
            }
            guard tasks.receiptFamily(involving: id) == family,
                closing.allSatisfy({ target in
                    let session = target.session
                    return sessions[session.id] === session && agents[session.record.agentID] === target.link
                        && target.link.generation == target.generation
                        && session.record.agentSessionID == target.agentSessionID
                        && session.lastEventAt == target.lastEventAt && session.loadGeneration == target.loadGeneration
                        && !participatesInCoordination(session, retainingSettledReceipts: false)
                        && !session.holdsRestart && !session.isStopping && session.queue.isEmpty
                })
            else {
                throw HostError.busy(
                    "The task changed while closing. Retry when it's ready. Its private files are kept.")
            }
            // Preserve receipt endpoints even if another member later refuses to close. A retry
            // must reload an acknowledged endpoint before sending it more work.
            unload(target.session, closingWith: nil)
        }
        try store.transaction {
            for target in closing { try store.keepClosedSessionConfig(target.session.record) }
        }
        for target in closing where !participatesInCoordination(target.session) {
            forget(target.session)
        }
    }
}
