import ACP
import Foundation
import NativeHostProtocol

// Sessions: starting them, adopting ones the agent has, loading them back into an agent process,
// and closing them.
extension HostCore {
    /// Starts a session on an agent. An id the host already has returns that session, so a client
    /// retrying after a dropped connection never starts two. With `follower`, that client follows
    /// the session's events from the first.
    func newSession(_ params: NewSessionParams, follower: ClientLink? = nil) async throws -> HostSessionSummary {
        if let id = params.sessionID, let existing = sessions[id] {
            follower.map { follow(existing, by: $0) }
            return existing.summary
        }
        let link = try await readyAgent(params.agentID)
        guard let peer = link.peer else { throw HostError.agentUnavailable(link.spec.name) }
        let response: RawNewSessionResponse
        do {
            response = try await peer.request(
                "session/new", RawNewSessionRequest(cwd: params.cwd, mcpServers: params.mcpServers, _meta: params.meta),
                as: RawNewSessionResponse.self)
        } catch {
            noteAgentError(error, from: link)
            throw error
        }
        if let id = params.sessionID, let existing = sessions[id] {
            // A retry got here first while the agent answered; this agent session goes unused.
            follower.map { follow(existing, by: $0) }
            return existing.summary
        }
        let record = StoredSession(
            id: params.sessionID ?? HostSessionID(), agentID: params.agentID, agentSessionID: response.sessionId,
            cwd: params.cwd, parentID: params.parentID, origin: params.origin, mcpServers: params.mcpServers,
            meta: params.meta)
        try store.insertSession(record)
        let session = HostSession(
            record: record, agentName: link.spec.name, phase: .idle, needsLoad: false, mcpServers: params.mcpServers)
        session.supportsSteering = link.supportsSteering
        sessions[record.id] = session
        follower.map { follow(session, by: $0) }
        append(.reset(loading: false), to: session)
        if let options = response.configOptions {
            append(.update(SessionMirror.configOptionsUpdate(options)), to: session)
        }
        route(session, on: link)
        publish(session)
        return session.summary
    }

    /// Adopts a session the agent already has, or returns the host session that already holds it.
    /// With `follower`, the answer comes once the session exists and the load goes on in the
    /// background, its replay streaming to the follower; otherwise the answer waits for the load.
    func openSession(_ params: OpenSessionParams, follower: ClientLink? = nil) async throws -> HostSessionSummary {
        if let existing = sessions.values.first(where: {
            $0.record.agentID == params.agentID && $0.record.agentSessionID == params.agentSessionID
        }) {
            if let follower {
                follow(existing, by: follower)
                loadInBackground(existing)
            } else {
                try await load(existing)
            }
            return existing.summary
        }
        guard let link = agents[params.agentID] else { throw HostError.unknownAgent(params.agentID) }
        let record = StoredSession(
            id: params.sessionID.flatMap { sessions[$0] == nil ? $0 : nil } ?? HostSessionID(),
            agentID: params.agentID, agentSessionID: params.agentSessionID, cwd: params.cwd,
            parentID: params.parentID, origin: params.origin, title: params.title, mcpServers: params.mcpServers,
            meta: params.meta, isAdopted: true)
        try store.insertSession(record)
        let session = HostSession(
            record: record, agentName: link.spec.name, phase: .loading, needsLoad: true, mcpServers: params.mcpServers)
        sessions[record.id] = session
        follower.map { follow(session, by: $0) }
        append(.reset(loading: false), to: session)
        publish(session)
        if follower != nil {
            loadInBackground(session)
        } else {
            try await load(session)
        }
        return session.summary
    }

    /// Subscribes a client to a session and replays its whole log to it, as `attach` does without
    /// `afterSeq`.
    func follow(_ session: HostSession, by client: ClientLink) {
        for event in session.events(after: nil) {
            client.notify(
                HostProtocol.Method.sessionEvent, SessionEventNotification(sessionID: session.id, event: event))
        }
        session.subscribers.insert(client.id)
        client.attached.insert(session.id)
    }

    func loadInBackground(_ session: HostSession) {
        guard session.needsLoad, session.record.origin != .announced else { return }
        Task { try? await load(session) }
    }

    /// Makes sure the agent process has the session loaded, replaying it from the agent's store if
    /// it doesn't (after the host or the agent restarted). Concurrent callers share one load.
    func load(_ session: HostSession) async throws {
        if let loading = session.loading {
            return try await loading.value
        }
        guard session.needsLoad else { return }
        let task = Task { try await performLoad(session) }
        session.loading = task
        defer { session.loading = nil }
        try await task.value
    }

    private func performLoad(_ session: HostSession) async throws {
        let wasRecovering = session.phase == .recovering
        if !wasRecovering {
            session.phase = .loading
        }
        publish(session)
        var replaying = false
        do {
            let link = try await readyAgent(session.record.agentID)
            guard let peer = link.peer, let agentSessionID = session.record.agentSessionID else {
                throw HostError.agentUnavailable(link.spec.name)
            }
            guard link.canLoadSessions else { throw HostError.cannotLoad(link.spec.name) }
            append(.reset(loading: true), to: session)
            replaying = true
            route(session, on: link)
            let response: RawConfigOptionsResponse
            do {
                response = try await peer.request(
                    "session/load",
                    RawLoadSessionRequest(
                        sessionId: agentSessionID, cwd: session.record.cwd, mcpServers: session.mcpServers,
                        _meta: session.record.meta),
                    as: RawConfigOptionsResponse.self)
            } catch let error as RPCError
                where !session.record.isAdopted && session.record.lastStopReason == nil && !error.isAuthRequired
            {
                // Agents save a session once a turn ends; one that never got that far has nothing to
                // load, so it carries on in a fresh agent session under the same host id.
                response = try await replaceUnsaved(session, on: link, peer: peer)
            } catch {
                noteAgentError(error, from: link)
                throw error
            }
            if let options = response.configOptions {
                append(.update(SessionMirror.configOptionsUpdate(options)), to: session)
            }
            append(.loaded, to: session)
            await restoreConfigChoices(of: session, on: link)
            session.needsLoad = false
            session.supportsSteering = link.supportsSteering
            session.problem = nil
            if !wasRecovering {
                session.phase = session.turn == nil ? .idle : .prompting
            }
            publish(session)
            if !wasRecovering {
                // Messages sent while it loaded.
                drainQueue(session)
            }
        } catch {
            if replaying {
                append(.loaded, to: session)
            }
            if !wasRecovering {
                session.phase = .disconnected
                append(
                    .notice(text: "Couldn't load this session: \(error.localizedDescription)", isError: true),
                    to: session)
            }
            session.problem = error.localizedDescription
            publish(session)
            throw error
        }
    }

    /// Starts a fresh agent session in place of one the agent never saved.
    private func replaceUnsaved(
        _ session: HostSession, on link: AgentLink, peer: JSONRPCPeer
    ) async throws -> RawConfigOptionsResponse {
        let response = try await peer.request(
            "session/new",
            RawNewSessionRequest(cwd: session.record.cwd, mcpServers: session.mcpServers, _meta: session.record.meta),
            as: RawNewSessionResponse.self)
        if let old = session.record.agentSessionID {
            link.routes[old] = nil
        }
        session.record.agentSessionID = response.sessionId
        try store.updateSession(session.record)
        route(session, on: link)
        return RawConfigOptionsResponse(configOptions: response.configOptions)
    }

    /// Sets back the config values clients chose where the reloaded session reports others (an agent
    /// may reopen a session on its default model), before anything else goes out.
    private func restoreConfigChoices(of session: HostSession, on link: AgentLink) async {
        guard let peer = link.peer, let agentSessionID = session.record.agentSessionID else { return }
        for (configID, value) in session.record.configChoices.sorted(by: { $0.key < $1.key }) {
            guard let option = session.mirror.state.configOptions.first(where: { $0.id == configID }),
                case .select(let current, let choices) = option.kind, current != value,
                choices.contains(where: { $0.value == value })
            else { continue }
            do {
                let response = try await peer.request(
                    "session/set_config_option",
                    RawSetConfigOptionRequest(sessionId: agentSessionID, configId: configID, value: value),
                    as: RawConfigOptionsResponse.self)
                if let options = response.configOptions {
                    append(.update(SessionMirror.configOptionsUpdate(options)), to: session)
                }
            } catch {
                logger.error("Couldn't set \(configID) back: \(error.localizedDescription)")
            }
        }
    }

    /// Points the agent's traffic for the session at it, delivering anything that arrived first.
    func route(_ session: HostSession, on link: AgentLink) {
        guard let agentSessionID = session.record.agentSessionID else { return }
        link.routes[agentSessionID] = session.id
        for update in link.buffered.removeValue(forKey: agentSessionID) ?? [] {
            apply(update, to: session, on: link)
        }
    }

    /// Replaces the MCP servers for the session's next load; a loaded session keeps the ones it has.
    func setMCPServers(_ params: SetMCPServersParams) throws {
        let session = try session(params.sessionID)
        session.record.mcpServers = params.mcpServers
        session.mcpServers = params.mcpServers
        try store.updateSession(session.record)
    }

    /// Stops tracking a session, and with `closeInAgent` frees it in the agent's process too (where
    /// the agent can). Its history stays with the agent.
    func closeSession(_ id: HostSessionID, closeInAgent: Bool = false) async throws {
        let session = try session(id)
        await cancel(session)
        forget(session)
        let link = agents[session.record.agentID]
        if closeInAgent, let agentSessionID = session.record.agentSessionID, !session.needsLoad,
            link?.capabilities?.closeSessions == true, let peer = link?.peer
        {
            _ = try? await peer.request(
                "session/close", RawSessionIDRequest(sessionId: agentSessionID), as: JSONValue.self)
        }
    }

    /// Drops a session (and the subagents under it) from the host and tells clients.
    func forget(_ session: HostSession) {
        session.retryTask?.cancel()
        session.stopTimeout?.cancel()
        try? store.deleteSession(session.id)
        sessions[session.id] = nil
        if let agentSessionID = session.record.agentSessionID {
            agents[session.record.agentID]?.routes[agentSessionID] = nil
        }
        for client in clients.values {
            client.attached.remove(session.id)
            client.notify(HostProtocol.Method.sessionClosed, SessionParams(sessionID: session.id))
        }
        for child in sessions.values where child.record.parentID == session.id && child.record.origin == .announced {
            forget(child)
        }
    }
}
