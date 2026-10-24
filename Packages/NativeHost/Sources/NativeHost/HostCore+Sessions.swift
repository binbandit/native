import ACP
import Foundation
import NativeHostProtocol

// Sessions: starting them, adopting ones the agent has, loading them back into an agent process,
// and closing them.
extension HostCore {
    /// Starts a session on an agent. An id the host already has returns that session, so a client
    /// retrying after a dropped connection never starts two. With `follower`, that client follows
    /// the session's events from the first.
    func newSession(
        _ params: NewSessionParams, follower: ClientLink? = nil, coordinator: NewCoordinatorParams? = nil
    ) async throws -> HostSessionSummary {
        if let id = params.sessionID, let existing = sessions[id] {
            follower.map { follow(existing, by: $0) }
            return existing.summary
        }
        let link = try await readyAgent(params.agentID)
        guard let peer = link.peer else { throw HostError.agentUnavailable(link.spec.name) }
        let sessionID = params.sessionID ?? HostSessionID()
        let servers = await tasks.agentServers(for: sessionID, base: params.mcpServers)
        let response: RawNewSessionResponse
        do {
            response = try await peer.request(
                "session/new", RawNewSessionRequest(cwd: params.cwd, mcpServers: servers, _meta: params.meta),
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
        let initialOptions: JSONValue?
        let record: StoredSession
        do {
            if coordinator != nil {
                initialOptions = try await coordinatorReadOnly(response, on: peer)
            } else {
                initialOptions = response.configOptions
            }
            record = StoredSession(
                id: sessionID, agentID: params.agentID, agentSessionID: response.sessionId,
                cwd: params.cwd, parentID: params.parentID, origin: params.origin, mcpServers: params.mcpServers,
                meta: params.meta,
                configChoices: initialOptions.map { Self.configValues(Self.configOptions($0)) } ?? [:])
            try store.transaction {
                if let coordinator {
                    let identity = HostTaskIdentity(agentID: params.agentID, agentSessionID: response.sessionId)
                    try validateAssignments(coordinator.assignments, coordinator: identity)
                    let assignment = HostCoordinator(
                        task: identity, projectPath: params.cwd, assignments: coordinator.assignments,
                        hostSessionID: sessionID)
                    var updated = coordinators
                    updated.append(assignment)
                    try store.setMeta(
                        Self.coordinatorsKey, String(decoding: try JSONEncoder().encode(updated), as: UTF8.self))
                }
                try store.insertSession(record)
            }
        } catch {
            if coordinator != nil { await discardCoordinatorCandidate(response.sessionId, on: link, peer: peer) }
            throw error
        }
        if let coordinator {
            coordinators.append(
                HostCoordinator(
                    task: HostTaskIdentity(agentID: params.agentID, agentSessionID: response.sessionId),
                    projectPath: params.cwd, assignments: coordinator.assignments, hostSessionID: sessionID))
            for client in clients.values { client.notify(HostProtocol.Method.coordinatorsChanged, coordinators) }
        }
        let session = HostSession(
            record: record, agentName: link.spec.name, phase: .idle, needsLoad: false, mcpServers: params.mcpServers)
        session.supportsSteering = link.supportsSteering
        sessions[record.id] = session
        follower.map { follow(session, by: $0) }
        append(.reset(loading: false), to: session)
        if let options = initialOptions {
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
            if existing.needsLoad, existing.loading == nil {
                existing.loadConfigDefaults = params.configDefaults ?? [:]
            }
            if let follower {
                follow(existing, by: follower)
                loadInBackground(existing)
            } else {
                try await load(existing)
            }
            return existing.summary
        }
        guard let link = agents[params.agentID] else { throw HostError.unknownAgent(params.agentID) }
        let config = try store.closedSessionConfig(agentID: params.agentID, agentSessionID: params.agentSessionID)
        let record = StoredSession(
            id: params.sessionID.flatMap { sessions[$0] == nil ? $0 : nil } ?? HostSessionID(),
            agentID: params.agentID, agentSessionID: params.agentSessionID, cwd: params.cwd,
            parentID: params.parentID, origin: params.origin, title: params.title, mcpServers: params.mcpServers,
            meta: params.meta, configChoices: config ?? params.configChoices ?? [:], isAdopted: true)
        try store.insertSession(record)
        let session = HostSession(
            record: record, agentName: link.spec.name, phase: .loading, needsLoad: true, mcpServers: params.mcpServers)
        session.loadConfigDefaults = params.configDefaults ?? [:]
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
        client.send(session.events(after: nil), of: session.id)
        session.subscribers.insert(client.id)
        client.attached.insert(session.id)
    }

    /// Loads the session if the agent doesn't have it, except one the host unloaded while idle,
    /// which waits until it's used: its log already shows everything.
    func loadInBackground(_ session: HostSession) {
        guard session.needsLoad, !session.reloadsQuietly, session.record.origin != .announced else { return }
        Task { try? await load(session) }
    }

    /// Makes sure the agent process has the session loaded, replaying it from the agent's store if
    /// it doesn't (after the host or the agent restarted), or resuming it quietly if the host
    /// unloaded it while idle. Concurrent callers share one load.
    func load(_ session: HostSession) async throws {
        try await agents[session.record.agentID]?.waitForCommandStop()
        if let loading = session.loading {
            return try await loading.value
        }
        guard session.needsLoad else { return }
        let task = Task {
            // Recovery reads the replay to tell whether the agent had the interrupted prompt.
            if session.reloadsQuietly, session.phase != .recovering {
                do {
                    return try await reloadQuietly(session)
                } catch {
                    logger.error("Couldn't resume a session quietly, loading it: \(error.localizedDescription)")
                }
            }
            // A load starts the log over, so it no longer holds the conversation to resume.
            session.reloadsQuietly = false
            try await performLoad(session)
        }
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
        session.loadingConfigOptions = nil
        defer { session.loadingConfigOptions = nil }
        do {
            let link = try await readyAgent(session.record.agentID)
            guard let peer = link.peer, let agentSessionID = session.record.agentSessionID else {
                throw HostError.agentUnavailable(link.spec.name)
            }
            let generation = link.generation
            guard link.canLoadSessions else { throw HostError.cannotLoad(link.spec.name) }
            let servers = await tasks.agentServers(for: session.id, base: session.mcpServers)
            discardSubagentsForReplay(of: session, on: link)
            append(.reset(loading: true), to: session)
            replaying = true
            route(session, on: link)
            let response: RawConfigOptionsResponse
            do {
                response = try await peer.request(
                    "session/load",
                    RawLoadSessionRequest(
                        sessionId: agentSessionID, cwd: session.record.cwd, mcpServers: servers,
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
            guard generation == link.generation else { throw PeerError.closed }
            // Inside the load, so clients get where the settings end up rather than the agent's defaults.
            try await restoreConfigChoices(of: session, on: link, reported: response.configOptions)
            if !wasRecovering {
                showPendingMessage(of: session)
            }
            append(.loaded, to: session)
            tasks.sessionLoaded(session)
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
                if !wasRecovering {
                    showPendingMessage(of: session)
                }
                append(.loaded, to: session)
            }
            if !wasRecovering {
                session.phase = .disconnected
                append(
                    .notice(text: "Couldn't load this task: \(error.localizedDescription)", isError: true),
                    to: session)
            }
            session.problem = error.localizedDescription
            publish(session)
            throw error
        }
    }

    /// Starts a fresh agent session in place of one the agent never saved.
    func replaceUnsaved(
        _ session: HostSession, on link: AgentLink, peer: JSONRPCPeer
    ) async throws -> RawConfigOptionsResponse {
        let servers = await tasks.agentServers(for: session.id, base: session.mcpServers)
        let response = try await peer.request(
            "session/new",
            RawNewSessionRequest(cwd: session.record.cwd, mcpServers: servers, _meta: session.record.meta),
            as: RawNewSessionResponse.self)
        let old = session.record.agentSessionID
        if let old {
            link.routes[old] = nil
        }
        session.record.agentSessionID = response.sessionId
        try store.updateSession(session.record)
        if let old {
            tasks.agentSessionReplaced(agent: session.record.agentID, old: old, new: response.sessionId)
        }
        route(session, on: link)
        return RawConfigOptionsResponse(configOptions: response.configOptions)
    }

    /// Sets back the settings the session ran with (`pinConfig`) where the reloaded session reports
    /// others (an agent may reopen a session on its default model, or on built-in defaults), before
    /// anything else goes out. In the order the app restores them (`ConfigChoices.restoreOrder`): the
    /// model first, since choosing it can put the effort back to the model's default, and each
    /// against the options as they are by then. It starts from the options the load `reported`, and
    /// only where they end up goes in the log, so clients never see the agent's defaults on the way.
    func restoreConfigChoices(of session: HostSession, on link: AgentLink, reported: JSONValue?) async throws {
        guard let peer = link.peer, let agentSessionID = session.record.agentSessionID else { throw PeerError.closed }
        let generation = link.generation
        var latest = reported ?? session.loadingConfigOptions
        var options = latest.map(Self.configOptions) ?? session.mirror.state.configOptions
        let saved = session.record.configChoices
        var choices = ConfigChoices()
        var attempted: Set<String> = []
        while true {
            // A model change can introduce an option absent from the load's initial response.
            for (configID, value) in saved where choices.choices[configID] == nil {
                if let option = options.first(where: { $0.id == configID }) {
                    choices.choose(option, value: value)
                }
            }
            choices = choices.fillingDefaults(session.loadConfigDefaults, in: options)
            guard let configID = choices.restoreOrder(in: options).first(where: { !attempted.contains($0) }) else {
                break
            }
            attempted.insert(configID)
            guard
                case .set(_, let value)? = choices.restoration(
                    of: configID, in: options, allows: { _, _ in true })
            else { continue }
            session.loadingConfigOptions = nil
            do {
                let response = try await peer.request(
                    "session/set_config_option",
                    RawSetConfigOptionRequest(sessionId: agentSessionID, configId: configID, value: value),
                    as: RawConfigOptionsResponse.self)
                if let reported = response.configOptions ?? session.loadingConfigOptions {
                    latest = reported
                    options = Self.configOptions(reported)
                }
            } catch let error as RPCError {
                logger.error("Couldn't set \(configID) back: \(error.localizedDescription)")
            }
            guard generation == link.generation else { throw PeerError.closed }
        }
        if let latest, Self.configOptions(latest) != session.mirror.state.configOptions {
            append(.update(SessionMirror.configOptionsUpdate(latest)), to: session)
        }
        noteUntaken(choices, saved: saved, in: session, now: options)
        // From here it runs with what the agent reports, a value it didn't take back included, so
        // the next reload sets back these rather than asking for that value again.
        pinConfig(options, of: session)
        session.loadConfigDefaults = [:]
    }

    /// A rejected or removed setting must not silently change how the resumed task runs.
    private func noteUntaken(
        _ choices: ConfigChoices, saved: [String: String], in session: HostSession, now options: [ConfigOption]
    ) {
        guard !options.isEmpty else { return }
        var notes: [String] = []
        var retryCount = 0
        for configID in choices.restoreOrder(in: options) {
            switch choices.restoration(of: configID, in: options, allows: { _, _ in true }) {
            case .set(let option, _)?:
                guard case .select(let current, let values) = option.kind, let choice = choices.choices[configID]
                else { continue }
                let currentName = values.first { $0.value == current }?.name ?? current
                notes.append(
                    "\(session.agentName) didn't take back \(choice.valueName) for \(option.name), so this task uses \(currentName)."
                )
                retryCount += 1
            case .unavailable(let choice, let kept)?:
                notes.append(
                    "\(session.agentName) no longer offers \(choice.valueName) for \(choice.optionName)."
                        + (kept.map { " This task uses \($0)." } ?? ""))
            default: break
            }
        }
        for configID in saved.keys.sorted() where choices.choices[configID] == nil {
            if let value = saved[configID] {
                notes.append(
                    "\(session.agentName) no longer offers the \(configID) setting, so it couldn't restore \(value).")
            }
        }
        guard !notes.isEmpty else { return }
        if retryCount > 0 {
            notes.append(retryCount == 1 ? "Choose it again to retry." : "Choose them again to retry.")
        } else {
            notes.append("Review this task's settings to choose another value.")
        }
        append(.notice(text: notes.joined(separator: " "), isError: false), to: session)
    }

    /// The options an agent reported, read the way clients read them.
    static func configOptions(_ reported: JSONValue) -> [ConfigOption] {
        guard let data = try? JSONEncoder().encode(reported) else { return [] }
        return (try? JSONDecoder().decode([ConfigOption].self, from: data)) ?? []
    }

    /// Pins what the session runs with: every setting's value as its agent reports it now, whether a
    /// client chose it, the agent changed it itself (leaving Plan Mode), or it's what the agent
    /// started the session on. A reload that comes back on others gets these set back, so resumed
    /// work runs as it did. New sessions never take them: they start on the agent's defaults.
    func pinConfig(_ options: [ConfigOption], of session: HostSession) {
        let values = Self.configValues(options)
        guard !values.isEmpty, values != session.record.configChoices else { return }
        session.record.configChoices = values
        try? store.updateSession(session.record)
    }

    /// Each select option's value, by option id.
    static func configValues(_ options: [ConfigOption]) -> [String: String] {
        Dictionary(
            options.compactMap { option in
                guard case .select(let current, _) = option.kind else { return nil }
                return (option.id, current)
            }, uniquingKeysWith: { first, _ in first })
    }

    /// Points the agent's traffic for the session at it, delivering anything that arrived first.
    func route(_ session: HostSession, on link: AgentLink) {
        guard let agentSessionID = session.record.agentSessionID else { return }
        link.routes[agentSessionID] = session.id
        for update in link.buffered.removeValue(forKey: agentSessionID) ?? [] {
            apply(update, to: session, on: link)
        }
    }

    /// Replaces the MCP servers for the session's next load: all of them, or (`replacingNamed`) the
    /// ones named, adding those it lacks. A loaded session keeps the ones it has. Nothing is written
    /// when nothing changed.
    func setMCPServers(_ params: SetMCPServersParams) throws {
        let session = try session(params.sessionID)
        var servers = params.mcpServers
        if params.replacingNamed {
            servers = session.record.mcpServers
            for server in params.mcpServers {
                let name = server["name"]?.stringValue
                if let index = servers.firstIndex(where: { $0["name"]?.stringValue == name }) {
                    servers[index] = server
                } else {
                    servers.append(server)
                }
            }
        }
        guard servers != session.record.mcpServers else { return }
        session.record.mcpServers = servers
        session.mcpServers = servers
        try store.updateSession(session.record)
    }

    /// Stops tracking a session, and with `closeInAgent` frees it in the agent's process too (where
    /// the agent can). Its history stays with the agent.
    func closeSession(_ id: HostSessionID, closeInAgent: Bool = false) async throws {
        let session = try session(id)
        // Coordination owns the durable record after the app stops displaying its transcript.
        // Reuse idle unloading so a later tool call resumes the task with its history and settings.
        if participatesInCoordination(session) {
            if closeInAgent { unloadIfIdle(session) }
            return
        }
        await cancel(session)
        try store.keepClosedSessionConfig(session.record)
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
        if !session.isStopping { session.stopTimeout?.cancel() }
        try? store.deleteSession(session.id)
        sessions[session.id] = nil
        tasks.sessionClosed(session)
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
