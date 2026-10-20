import ACP
import Foundation
import NativeHostProtocol

// Unloading idle sessions (docs/performance.md, "Idle, memory and leaks"). Some agents hold a lot
// for every session they have loaded (codex-acp starts the user's MCP servers for each one), and
// some keep things after closing one (codex-acp keeps the MCP servers of a thread it titled a
// session with). For an agent whose spec sets `idleUnloadTimeout`, a session idle that long is
// closed in the agent while the host keeps it, its log and its followers, so every client's
// transcript stays as it is; its next use resumes it without a replay. Once the agent has nothing
// loaded and nothing to do, its process ends too, which frees the rest; it starts again when
// something needs it.
extension HostCore {
    /// Checks for idle sessions and agents for as long as the host runs, a few times per timeout.
    func unloadIdleSessionsPeriodically() {
        Task { [weak self] in
            var interval = Duration.seconds(30)
            while !Task.isCancelled {
                try? await Task.sleep(for: interval, tolerance: interval / 10)
                guard let self else { return }
                unloadIdleSessions()
                interval = idleUnloadCheckInterval
            }
        }
    }

    /// Unloads the sessions that sat idle for their agent's `idleUnloadTimeout`, then ends the agents
    /// that have nothing loaded, nothing under way and haven't been used for as long.
    func unloadIdleSessions(now: Date = .now) {
        for link in agents.values {
            guard let seconds = link.spec.idleUnloadTimeout, link.status == .ready, let peer = link.peer,
                link.capabilities?.closeSessions == true, link.capabilities?.resumeSessions == true
            else { continue }
            let timeout = TimeInterval(seconds)
            let theirs = sessions.values.filter { $0.record.agentID == link.spec.id }
            let idle = Set(
                theirs.filter { canUnload($0) && now.timeIntervalSince(lastUse(of: $0)) >= timeout }.map(\.id))
            let lastUse = theirs.map(\.lastEventAt).max() ?? .distantPast
            let endsAgent =
                !theirs.contains { holdsAgent($0) && !idle.contains($0.id) } && !peer.hasPendingRequests
                && now.timeIntervalSince(max(link.readyAt, lastUse)) >= timeout
            for session in theirs where idle.contains(session.id) {
                // Ending the process closes them all at once.
                unload(session, closingWith: endsAgent ? nil : peer)
            }
            guard endsAgent else { continue }
            logger.info("Stopping \(link.spec.name), which has nothing loaded")
            let generation = link.generation
            link.end()
            agentExited(link.spec.id, generation: generation)
        }
    }

    /// Often enough to unload within a quarter of the shortest timeout, at most every 30 s.
    private var idleUnloadCheckInterval: Duration {
        guard let shortest = agents.values.compactMap(\.spec.idleUnloadTimeout).min() else { return .seconds(30) }
        return .seconds(min(30, max(1, Double(shortest) / 4)))
    }

    /// Whether closing the session in its agent now would cut nothing off: it's loaded, idle, and
    /// nothing it or its subagents run waits on the agent or the user.
    private func canUnload(_ session: HostSession) -> Bool {
        !session.needsLoad && session.loading == nil && session.phase == .idle && !session.isWorking
            && session.record.origin != .announced && session.record.agentSessionID != nil
            && session.pendingPermissions.isEmpty && session.pendingQuestions.isEmpty
            && !subagents(of: session).contains(where: \.isWorking)
    }

    /// The session's last event, or its subagents' if they're later: they report through it.
    private func lastUse(of session: HostSession) -> Date {
        subagents(of: session).map(\.lastEventAt).reduce(session.lastEventAt, max)
    }

    /// Whether the session keeps its agent's process needed: it's loaded or loading, or something
    /// it runs waits on the agent.
    private func holdsAgent(_ session: HostSession) -> Bool {
        !session.needsLoad || session.loading != nil || session.isWorking || !session.pendingPermissions.isEmpty
            || !session.pendingQuestions.isEmpty
    }

    private func subagents(of session: HostSession) -> [HostSession] {
        sessions.values.filter { $0.record.parentID == session.id && $0.record.origin == .announced }
    }

    /// Closes the session in its agent (with `peer`, unless the agent is about to end), keeping it
    /// here as it is. From now on it needs a load, which resumes it quietly; a request sent after
    /// the close reaches the agent after it.
    private func unload(_ session: HostSession, closingWith peer: JSONRPCPeer?) {
        session.needsLoad = true
        session.reloadsQuietly = true
        // They live in the parent's agent session, which takes them with it.
        for subagent in subagents(of: session) {
            subagent.needsLoad = true
        }
        logger.info("Unloading an idle \(session.agentName) session")
        guard let peer, let agentSessionID = session.record.agentSessionID else { return }
        Task {
            do {
                _ = try await peer.request(
                    "session/close", RawSessionIDRequest(sessionId: agentSessionID), as: JSONValue.self)
            } catch {
                logger.error("Couldn't unload a \(session.agentName) session: \(error.localizedDescription)")
            }
        }
    }
}
