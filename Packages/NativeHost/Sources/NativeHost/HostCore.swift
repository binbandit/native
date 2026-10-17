import ACP
import Foundation
import NativeHostProtocol

/// The host: owns the agents, the sessions and the store, and serves clients. Turns live in
/// `HostCore+Turns.swift`, recovery in `HostCore+Recovery.swift`, the client protocol in
/// `HostCore+Clients.swift`.
@HostActor
public final class HostCore {
    public struct Configuration: Sendable {
        public var location: HostLocation
        public var hostInfo: PeerInfo
        public var machineName: String
        /// When this machine booted, to tell a restart of the Mac from the host stopping.
        public var bootTime: Date?
        /// The environment agents launch with: the user's login-shell environment.
        public var environment: @Sendable () async -> [String: String]
        /// How often the host notes that it's alive, which dates an interruption it didn't see.
        public var heartbeatInterval: Duration
        /// Called when the host should exit, with the status to exit with.
        public var exit: @Sendable (Int32) -> Void
        /// Development hosts stop after this long with no clients and nothing running, so hosts of
        /// builds nobody uses don't linger. Nil for release hosts, which stay up.
        public var idleExit: Duration?

        public init(
            location: HostLocation, hostInfo: PeerInfo, machineName: String, bootTime: Date?,
            environment: @escaping @Sendable () async -> [String: String], heartbeatInterval: Duration = .seconds(30),
            idleExit: Duration? = nil, exit: @escaping @Sendable (Int32) -> Void
        ) {
            self.location = location
            self.hostInfo = hostInfo
            self.machineName = machineName
            self.bootTime = bootTime
            self.environment = environment
            self.heartbeatInterval = heartbeatInterval
            self.idleExit = idleExit
            self.exit = exit
        }
    }

    /// Exit statuses. launchd restarts the host after any status but `stopped`.
    public enum ExitStatus {
        /// Stopped on purpose; stay down until the app starts the host again.
        public static let stopped: Int32 = 0
        /// Exiting so launchd starts the (newer) binary again, as after an update.
        public static let restart: Int32 = 75
    }

    let configuration: Configuration
    let store: HostStore
    let hostID: HostID
    let epoch = UUID()
    let startedAt = Date.now
    var agents: [String: AgentLink] = [:]
    var sessions: [HostSessionID: HostSession] = [:]
    var clients: [ClientLink.ID: ClientLink] = [:]
    /// Set once a restart was asked for, to exit when nothing is running.
    var isRestartingWhenIdle = false
    let logger = HostLogger(category: "Host")
    private var environment: Task<[String: String], Never>?
    private var heartbeat: Task<Void, Never>?
    private var server: SocketServer?
    /// When the host last had a client or a running turn, for `Configuration.idleExit`.
    private var lastBusy = Date.now

    public init(configuration: Configuration) throws {
        self.configuration = configuration
        try configuration.location.prepare()
        store = try HostStore(url: configuration.location.databaseURL)
        if let id = try store.meta(MetaKey.hostID).flatMap(UUID.init(uuidString:)) {
            hostID = HostID(id)
        } else {
            hostID = HostID()
            try store.setMeta(MetaKey.hostID, hostID.description)
        }
        for spec in try store.agents() {
            agents[spec.id] = AgentLink(spec: spec)
        }
        let queues = try store.sessions().map { record in (record, try store.queue(for: record.id)) }
        for (record, queue) in queues {
            let session = HostSession(
                record: record, agentName: agents[record.agentID]?.spec.name ?? record.agentID, phase: .idle,
                needsLoad: true, mcpServers: record.mcpServers)
            session.queue = queue.map { StoredQueueItem(prompt: $0.prompt, isSteering: false) }
            sessions[record.id] = session
            _ = session.append(.reset(loading: false))
        }
        try store.pruneRequests(olderThan: .now.addingTimeInterval(-7 * 24 * 3600))
    }

    /// Picks up what the previous run left unfinished, then keeps a heartbeat.
    public func start() {
        do {
            try resumeInterruptedWork()
        } catch {
            logger.error("Couldn't read what to recover: \(error.localizedDescription)")
        }
        let interval = configuration.heartbeatInterval
        heartbeat = Task { [weak self] in
            while !Task.isCancelled {
                self?.beat()
                try? await Task.sleep(for: interval)
            }
        }
    }

    /// Keeps the socket server alive as long as the host.
    func retain(_ server: SocketServer) {
        self.server = server
    }

    var info: HostInfo {
        HostInfo(
            protocolVersion: HostProtocol.version, hostID: hostID, machineName: configuration.machineName,
            hostInfo: configuration.hostInfo,
            epoch: epoch, processID: ProcessInfo.processInfo.processIdentifier, startedAt: startedAt,
            channel: configuration.location.channel
        )
    }

    private func beat() {
        try? store.setMeta(MetaKey.heartbeat, String(Date.now.timeIntervalSince1970))
        guard let idleExit = configuration.idleExit else { return }
        let isBusy =
            !clients.isEmpty
            || sessions.values.contains { $0.turn != nil || $0.phase == .recovering || $0.phase == .loading }
        if isBusy {
            lastBusy = .now
        } else if Date.now.timeIntervalSince(lastBusy) > Double(idleExit.components.seconds) {
            logger.info("Idle development host stopping")
            for link in agents.values {
                link.stop()
            }
            try? store.setMeta(MetaKey.cleanShutdown, "1")
            configuration.exit(ExitStatus.stopped)
        }
    }

    // MARK: - Environment and agents

    /// The login-shell environment, read once and shared.
    func agentEnvironment() async -> [String: String] {
        if let environment {
            return await environment.value
        }
        let provider = configuration.environment
        let task = Task { await provider() }
        environment = task
        return await task.value
    }

    func syncAgents(_ specs: [AgentSpec]) throws {
        try store.replaceAgents(specs)
        for spec in specs {
            if let link = agents[spec.id] {
                // A changed launch command applies the next time the agent starts.
                link.spec = spec
            } else {
                agents[spec.id] = AgentLink(spec: spec)
            }
        }
        for session in sessions.values {
            session.agentName = agents[session.record.agentID]?.spec.name ?? session.agentName
        }
    }

    /// The running agent for `agentID`, started if needed.
    func readyAgent(_ agentID: String) async throws -> AgentLink {
        guard let link = agents[agentID] else { throw HostError.unknownAgent(agentID) }
        let environment: @Sendable () async -> [String: String] = { [weak self] in await self?.agentEnvironment() ?? [:]
        }
        let clientInfo = Implementation(name: "native-host", title: "Native", version: configuration.hostInfo.version)
        try await link.ensureStarted(environment: environment, clientInfo: clientInfo) {
            [weak self] generation, event in
            await self?.receive(event, from: agentID, generation: generation)
        }
        return link
    }

    // MARK: - Sessions

    func session(_ id: HostSessionID) throws -> HostSession {
        guard let session = sessions[id] else { throw HostError.unknownSession(id) }
        return session
    }

    func newSession(_ params: NewSessionParams) async throws -> HostSessionSummary {
        let link = try await readyAgent(params.agentID)
        guard let peer = link.peer else { throw HostError.agentUnavailable(link.spec.name) }
        let record = StoredSession(
            id: HostSessionID(), agentID: params.agentID, agentSessionID: nil, cwd: params.cwd,
            parentID: params.parentID,
            origin: params.origin, mcpServers: params.mcpServers
        )
        let response = try await peer.request(
            "session/new", RawNewSessionRequest(cwd: params.cwd, mcpServers: params.mcpServers),
            as: RawNewSessionResponse.self
        )
        var stored = record
        stored.agentSessionID = response.sessionId
        try store.insertSession(stored)
        let session = HostSession(
            record: stored, agentName: link.spec.name, phase: .idle, needsLoad: false, mcpServers: params.mcpServers)
        session.supportsSteering = link.supportsSteering
        sessions[stored.id] = session
        append(.reset(loading: false), to: session)
        if let options = response.configOptions {
            append(.update(SessionMirror.configOptionsUpdate(options)), to: session)
        }
        route(session, on: link)
        publish(session)
        return session.summary
    }

    /// Adopts a session the agent already has, or returns the host session that already holds it.
    func openSession(_ params: OpenSessionParams) async throws -> HostSessionSummary {
        if let existing = sessions.values.first(where: {
            $0.record.agentID == params.agentID && $0.record.agentSessionID == params.agentSessionID
        }) {
            try await load(existing)
            return existing.summary
        }
        guard let link = agents[params.agentID] else { throw HostError.unknownAgent(params.agentID) }
        let record = StoredSession(
            id: HostSessionID(), agentID: params.agentID, agentSessionID: params.agentSessionID, cwd: params.cwd,
            parentID: nil,
            origin: .user, title: params.title, mcpServers: params.mcpServers
        )
        try store.insertSession(record)
        let session = HostSession(
            record: record, agentName: link.spec.name, phase: .idle, needsLoad: true, mcpServers: params.mcpServers)
        sessions[record.id] = session
        append(.reset(loading: false), to: session)
        publish(session)
        try await load(session)
        return session.summary
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
        do {
            let link = try await readyAgent(session.record.agentID)
            guard let peer = link.peer, let agentSessionID = session.record.agentSessionID else {
                throw HostError.agentUnavailable(link.spec.name)
            }
            guard link.canLoadSessions else { throw HostError.cannotLoad(link.spec.name) }
            append(.reset(loading: true), to: session)
            route(session, on: link)
            let response = try await peer.request(
                "session/load",
                RawLoadSessionRequest(
                    sessionId: agentSessionID, cwd: session.record.cwd, mcpServers: session.mcpServers),
                as: RawConfigOptionsResponse.self
            )
            if let options = response.configOptions {
                append(.update(SessionMirror.configOptionsUpdate(options)), to: session)
            }
            append(.loaded, to: session)
            session.needsLoad = false
            session.supportsSteering = link.supportsSteering
            session.problem = nil
            if !wasRecovering {
                session.phase = session.turn == nil ? .idle : .prompting
            }
            publish(session)
        } catch {
            if !wasRecovering {
                session.phase = .disconnected
            }
            session.problem = error.localizedDescription
            publish(session)
            throw error
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

    func closeSession(_ id: HostSessionID) async throws {
        let session = try session(id)
        await cancel(session)
        try store.deleteSession(id)
        sessions[id] = nil
        if let agentSessionID = session.record.agentSessionID {
            agents[session.record.agentID]?.routes[agentSessionID] = nil
        }
        for client in clients.values {
            client.attached.remove(id)
            client.notify(HostProtocol.Method.sessionClosed, SessionParams(sessionID: id))
        }
    }

    // MARK: - Agent traffic

    func receive(_ event: JSONRPCPeer.Event, from agentID: String, generation: Int) {
        guard let link = agents[agentID], link.generation == generation else { return }
        switch event {
        case .notification(let message) where message.method == "session/update":
            guard let notification = try? message.params(as: RawSessionNotification.self) else { return }
            if let id = link.routes[notification.sessionId], let session = sessions[id] {
                apply(notification.update, to: session, on: link)
            } else {
                link.buffer(notification.update, for: notification.sessionId)
            }
        case .notification:
            break
        case .request(let message):
            receiveRequest(message, from: link)
        case .closed:
            agentExited(agentID, generation: generation)
        }
    }

    private func receiveRequest(_ message: JSONRPCPeer.Message, from link: AgentLink) {
        guard let id = message.id, let peer = link.peer else { return }
        guard message.method == "session/request_permission" else {
            // Native advertises no optional client capabilities, so anything else (fs, terminals)
            // is unexpected.
            try? peer.respond(to: id, error: .methodNotFound(message.method))
            return
        }
        guard let request = try? message.params(as: RawPermissionRequest.self), let raw = message.rawParams,
            let sessionID = link.routes[request.sessionId], let session = sessions[sessionID]
        else {
            try? peer.respond(to: id, with: RequestPermissionResponse.cancelled)
            return
        }
        let toolCallID = request.toolCall.toolCallId
        session.pendingPermissions[toolCallID] = id
        append(.permissionRequested(toolCallID: toolCallID, request: raw), to: session)
        try? store.addApproval(sessionID: session.id, toolCallID: toolCallID, title: request.toolCall.title)
        journal(.approvalNeeded, session: session, detail: request.toolCall.title)
        publish(session)
    }

    /// An agent update for a session. A subagent the agent announces becomes a session of its own,
    /// so its traffic has somewhere to go.
    func apply(_ update: JSONValue, to session: HostSession, on link: AgentLink) {
        if update["sessionUpdate"]?.stringValue == "subagent_update"
            || update["sessionUpdate"]?.stringValue == "subagent_spawned",
            let child = update["sessionId"]?.stringValue.map(SessionID.init), link.routes[child] == nil
        {
            adoptSubagent(child, of: session, on: link)
        }
        let hadTitle = session.record.title
        append(.update(update), to: session)
        if session.record.title != hadTitle {
            try? store.updateSession(session.record)
            publish(session)
        }
    }

    private func adoptSubagent(_ agentSessionID: SessionID, of parent: HostSession, on link: AgentLink) {
        // Subagents live as long as their parent's agent process; the parent's replay brings them back.
        let record = StoredSession(
            id: HostSessionID(), agentID: parent.record.agentID, agentSessionID: agentSessionID, cwd: parent.record.cwd,
            parentID: parent.id, origin: .announced
        )
        let child = HostSession(record: record, agentName: parent.agentName, phase: .idle, needsLoad: false)
        sessions[record.id] = child
        append(.reset(loading: false), to: child)
        route(child, on: link)
        publish(child)
    }

    // MARK: - Events out

    /// Logs an event for a session and sends it to the clients following it.
    @discardableResult
    func append(_ payload: HostEvent.Payload, to session: HostSession) -> HostEvent {
        let event = session.append(payload)
        let notification = SessionEventNotification(sessionID: session.id, event: event)
        for id in session.subscribers {
            clients[id]?.notify(HostProtocol.Method.sessionEvent, notification)
        }
        return event
    }

    /// Tells every client the session's summary changed.
    func publish(_ session: HostSession) {
        let notification = SessionChangedNotification(summary: session.summary)
        for client in clients.values {
            client.notify(HostProtocol.Method.sessionChanged, notification)
        }
    }

    /// Records something the user may want to know about later, and tells clients.
    func journal(
        _ kind: ActivityEntry.Kind, session: HostSession?, detail: String? = nil, recovery: RecoveryNote? = nil
    ) {
        let subject = session.map { $0.record.title ?? $0.agentName }
        guard
            let entry = try? store.appendActivity(
                kind, session: session?.id, subject: subject, detail: detail, recovery: recovery)
        else { return }
        for client in clients.values {
            client.notify(HostProtocol.Method.activity, entry)
        }
    }
}
