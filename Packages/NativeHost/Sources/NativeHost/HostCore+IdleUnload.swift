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
    /// Checks for idle sessions and agents for as long as the host runs, a few times per timeout,
    /// starting over when agents' specs change.
    func unloadIdleSessionsPeriodically() {
        idleUnloadChecks?.cancel()
        idleUnloadChecks = Task { [weak self] in
            while let interval = self?.idleUnloadCheckInterval {
                try? await Task.sleep(for: interval, tolerance: interval / 10)
                guard !Task.isCancelled else { return }
                self?.unloadIdleSessions()
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
            && !session.mirror.state.subagents.contains { $0.workState?.isWorking == true }
            && !subagents(of: session).contains {
                $0.isWorking || !$0.pendingPermissions.isEmpty || !$0.pendingQuestions.isEmpty
                    || $0.mirror.state.subagents.contains { $0.workState?.isWorking == true }
            }
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

    /// Nested children share the parent's lifetime too, including their pending input and history.
    func subagents(of session: HostSession) -> [HostSession] {
        var descendants: [HostSession] = []
        var parents: Set<HostSessionID> = [session.id]
        var seen = parents
        while !parents.isEmpty {
            let children = sessions.values.filter {
                $0.record.origin == .announced && $0.record.parentID.map(parents.contains) == true
                    && !seen.contains($0.id)
            }
            descendants.append(contentsOf: children)
            parents = Set(children.map(\.id))
            seen.formUnion(parents)
        }
        return descendants
    }

    /// A full history replay reconstructs the child tree; keeping its old logs would duplicate it.
    func discardSubagentsForReplay(of session: HostSession, on link: AgentLink) {
        for child in subagents(of: session) {
            if let agentSessionID = child.record.agentSessionID {
                link.routes[agentSessionID] = nil
            }
            sessions[child.id] = nil
        }
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
            subagent.reloadsQuietly = true
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

    /// Brings back a session `unload` left, with `session/resume`, which replays nothing: its log
    /// still holds the conversation, so every client's transcript and the session's phase stay as
    /// they are. Its settings are set back where the agent reopened it on others. A session the
    /// agent never saved has nothing to resume, so it carries on in a fresh one.
    func reloadQuietly(_ session: HostSession) async throws {
        let link = try await readyAgent(session.record.agentID)
        guard let peer = link.peer, let agentSessionID = session.record.agentSessionID else {
            throw HostError.agentUnavailable(link.spec.name)
        }
        let generation = link.generation
        let children = subagents(of: session)
        // Register the whole tree before draining buffered updates, which can announce children again.
        for child in children {
            if let agentSessionID = child.record.agentSessionID {
                link.routes[agentSessionID] = child.id
            }
        }
        for child in children { route(child, on: link) }
        session.loadingConfigOptions = nil
        defer { session.loadingConfigOptions = nil }
        let response: RawConfigOptionsResponse
        do {
            if session.record.lastStopReason == nil && !session.record.isAdopted {
                response = try await replaceUnsaved(session, on: link, peer: peer)
            } else {
                let servers = await tasks.agentServers(for: session.id, base: session.mcpServers)
                route(session, on: link)
                response = try await peer.request(
                    "session/resume",
                    RawLoadSessionRequest(
                        sessionId: agentSessionID, cwd: session.record.cwd, mcpServers: servers,
                        _meta: session.record.meta),
                    as: RawConfigOptionsResponse.self)
            }
        } catch {
            noteAgentError(error, from: link)
            throw error
        }
        guard generation == link.generation else { throw PeerError.closed }
        try await restoreConfigChoices(of: session, on: link, reported: response.configOptions)
        tasks.sessionLoaded(session)
        session.needsLoad = false
        session.reloadsQuietly = false
        for child in children {
            child.needsLoad = false
            child.reloadsQuietly = false
        }
        session.supportsSteering = link.supportsSteering
        session.problem = nil
        publish(session)
    }
}
