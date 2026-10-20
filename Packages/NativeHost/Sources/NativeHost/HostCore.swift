import ACP
import Foundation
import NativeHostProtocol

/// The host: owns the agents, the sessions and the store, and serves clients. Sessions live in
/// `HostCore+Sessions.swift`, turns in `HostCore+Turns.swift`, recovery in
/// `HostCore+Recovery.swift`, agents in `HostCore+AgentControl.swift`, the client protocol in
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
        /// Where installed plugins live, a folder each: `~/.native/plugins` unless set.
        public var pluginsDirectory: URL
        /// How this host is updated (docs/releasing.md, "Remote updates").
        public var updates: HostUpdateEnvironment
        /// Development hosts stop after this long with no clients and nothing running, so hosts of
        /// builds nobody uses don't linger. Nil for release hosts, which stay up.
        public var idleExit: Duration?

        public init(
            location: HostLocation, hostInfo: PeerInfo, machineName: String, bootTime: Date?,
            environment: @escaping @Sendable () async -> [String: String], heartbeatInterval: Duration = .seconds(30),
            idleExit: Duration? = nil, pluginsDirectory: URL? = nil, updates: HostUpdateEnvironment? = nil,
            exit: @escaping @Sendable (Int32) -> Void
        ) {
            self.updates =
                updates
                ?? .none(
                    current: HostUpdateStatus.Build(
                        version: hostInfo.version, build: hostInfo.build, channel: "stable"),
                    reason: "This host wasn't installed by Native's updater, so it can't update itself.")
            self.pluginsDirectory =
                pluginsDirectory
                ?? FileManager.default.homeDirectoryForCurrentUser.appending(
                    path: ".native/plugins", directoryHint: .isDirectory)
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
    public let hostID: HostID
    let epoch = UUID()
    let startedAt = Date.now
    var agents: [String: AgentLink] = [:]
    /// The order clients listed the agents in.
    var agentOrder: [String] = []
    var sessions: [HostSessionID: HostSession] = [:]
    var clients: [ClientLink.ID: ClientLink] = [:]
    /// Prompt requests being handled, so a repeat of one waits for its answer instead of sending again.
    var promptsInFlight: [UUID: Task<PromptDelivery, any Error>] = [:]
    var pluginCatalog: PluginCatalog { PluginCatalog(directory: configuration.pluginsDirectory) }
    /// The catalog clients were last told about, to notify them only of real changes.
    var lastPublishedPlugins: [HostPlugin]?
    /// The update status, without what's computed per client (`HostCore+Updates.swift`).
    var updateState: HostUpdateStatus
    /// The Mac app's connection, once it reports Sparkle's status (provider `app`).
    var appUpdateClient: ClientLink.ID?
    /// A standalone build to switch to when the host next exits for a restart.
    var pendingActivation: String?
    var updateChecks: Task<Void, Never>?
    /// Set once a restart was asked for, to exit when nothing is running.
    var isRestartingWhenIdle = false
    let logger = HostLogger(category: "Host")
    /// The login-shell environment agents start with, read once (again after a sync asks).
    private var environment: Task<[String: String], Never>?
    private var heartbeat: Task<Void, Never>?
    private var server: SocketServer?
    /// When the host last had a client or a running turn, for `Configuration.idleExit`.
    private var lastBusy = Date.now

    public init(configuration: Configuration) throws {
        self.configuration = configuration
        updateState = Self.initialUpdateState(configuration.updates)
        try configuration.location.prepare()
        store = try HostStore(url: configuration.location.databaseURL)
        if let id = try store.meta(MetaKey.hostID).flatMap(UUID.init(uuidString:)) {
            hostID = HostID(id)
        } else {
            hostID = HostID()
            try store.setMeta(MetaKey.hostID, hostID.description)
        }
        let specs = try store.agents()
        agentOrder = specs.map(\.id)
        for spec in specs {
            agents[spec.id] = makeLink(spec)
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
        startUpdates()
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
        restartIfReplacedOnDisk()
        guard let idleExit = configuration.idleExit else { return }
        let isBusy =
            !clients.isEmpty
            || sessions.values.contains { $0.isWorking || $0.phase == .loading }
        if isBusy {
            lastBusy = .now
        } else if Date.now.timeIntervalSince(lastBusy) > Double(idleExit.components.seconds) {
            logger.info("Idle development host stopping")
            for link in agents.values {
                link.endNow()
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

    func syncAgents(_ specs: [AgentSpec], refreshEnvironment: Bool = false) throws {
        try store.replaceAgents(specs)
        if refreshEnvironment {
            environment = nil
        }
        agentOrder = specs.map(\.id)
        for spec in specs {
            if let link = agents[spec.id] {
                // A changed launch command applies the next time the agent starts.
                if link.spec != spec {
                    link.spec = spec
                    publishAgent(link)
                }
            } else {
                let link = makeLink(spec)
                agents[spec.id] = link
                publishAgent(link)
            }
        }
        for session in sessions.values {
            session.agentName = agents[session.record.agentID]?.spec.name ?? session.agentName
        }
    }

    private func makeLink(_ spec: AgentSpec) -> AgentLink {
        let link = AgentLink(spec: spec)
        link.onChange = { [weak self, weak link] in
            guard let self, let link else { return }
            publishAgent(link)
        }
        return link
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

    /// Tells every client an agent's status changed.
    func publishAgent(_ link: AgentLink) {
        let notification = AgentChangedNotification(agent: link.hostAgent)
        for client in clients.values {
            client.notify(HostProtocol.Method.agentChanged, notification)
        }
    }

    /// Records something the user may want to know about later, and tells clients.
    func journal(
        _ kind: ActivityEntry.Kind, session: HostSession?, detail: String? = nil, recovery: RecoveryNote? = nil,
        previousRun: ActivityEntry.RunEnding? = nil
    ) {
        let entry = ActivityEntry(
            id: 0, at: .now, sessionID: session?.id, agentID: session?.record.agentID,
            agentSessionID: session?.record.agentSessionID, kind: kind,
            subject: session.map { $0.record.title ?? $0.agentName }, detail: detail, recovery: recovery,
            previousRun: previousRun)
        guard let stored = try? store.appendActivity(entry) else { return }
        for client in clients.values {
            client.notify(HostProtocol.Method.activity, stored)
        }
    }
}
