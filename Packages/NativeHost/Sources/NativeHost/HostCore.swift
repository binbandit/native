import ACP
import Exec
import Foundation
import NativeHostProtocol
import NativeOrchestration
import SessionTitling

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
        /// Runs clients' commands (`_native/exec/run`). Nil means this machine's own runner where
        /// there is one (`LocalCommandRunner` on macOS and Linux); elsewhere the host can't run them.
        public var commands: (any CommandRunner)?
        /// Watches folders for `_native/fs/watch`: FSEvents on a Mac (`MacHost`). Nil polls
        /// (`PollingFileWatching`), which works anywhere.
        public var fileWatching: (any FileWatching)?
        /// The guides Native's tools serve agents (`list_skills`, `get_skill`): the app's copies of
        /// docs/setup.md and docs/plugins.md. Empty leaves those tools out.
        public var nativeSkills: [NativeSkill]
        /// Writes titles on this machine for `HostTitleProvider.onDevice`: the on-device model on a
        /// Mac (`MacHost`). Nil leaves titles to clients.
        public var titleGenerator: (any SessionTitleGenerator)?
        /// Holds power assertions for keeping awake: IOKit on a Mac (`MacHost`). Nil can't keep the
        /// machine awake, and says so.
        public var keepAwake: (any HostPowerBackend)?
        /// What `HostStatus` says about the machine; nil says what Foundation knows.
        public var systemInfo: HostSystemInfo?
        /// `_native/host/doctor`'s reads and platform checks; nil checks only keeping awake.
        public var doctor: HostDoctor?
        /// Keys the host keeps for agents' sign-in methods (`HostCredentials`): the keychain on a Mac
        /// (`MacHost`), else `credentials.json` in the host's directory.
        public var credentials: HostCredentials

        public init(
            location: HostLocation, hostInfo: PeerInfo, machineName: String, bootTime: Date?,
            environment: @escaping @Sendable () async -> [String: String], heartbeatInterval: Duration = .seconds(30),
            idleExit: Duration? = nil, pluginsDirectory: URL? = nil, updates: HostUpdateEnvironment? = nil,
            exit: @escaping @Sendable (Int32) -> Void, commands: (any CommandRunner)? = nil,
            fileWatching: (any FileWatching)? = nil, nativeSkills: [NativeSkill] = [],
            titleGenerator: (any SessionTitleGenerator)? = nil, keepAwake: (any HostPowerBackend)? = nil,
            systemInfo: HostSystemInfo? = nil, doctor: HostDoctor? = nil, credentials: (any HostCredentialStore)? = nil
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
            self.commands = commands
            self.fileWatching = fileWatching
            self.nativeSkills = nativeSkills
            self.titleGenerator = titleGenerator
            self.keepAwake = keepAwake
            self.systemInfo = systemInfo
            self.doctor = doctor
            self.credentials = HostCredentials(store: credentials ?? HostCredentialFile(directory: location.directory))
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
    /// Command cleanup outlives closing its task, and must finish before the host exits.
    var stoppingSessions: [HostSessionID: HostSession] = [:]
    /// Native's tools for agents and the tasks sessions hand each other (`HostTasks.swift`).
    lazy var tasks = HostTasks(core: self)
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
    /// Checks for sessions to unload while idle (`HostCore+IdleUnload.swift`).
    var idleUnloadChecks: Task<Void, Never>?
    /// Set once a restart was asked for, to exit when nothing is running.
    var isRestartingWhenIdle = false
    /// Quit and Stop Agents authorizes ending shared trees, including hidden commands.
    var isStoppingAllAgents = false
    /// Who writes titles, and which are being written (`HostCore+Titles.swift`).
    var titling = HostTitling()
    /// Keeps the machine awake while sessions work, as the policy says (`HostCore+Status.swift`).
    lazy var keepAwake = makeKeepAwake()
    /// The paired-device gateway's state for the doctor, set by the process that runs it.
    public var doctorGateway: (@Sendable () async -> HostDoctorGateway?)?
    /// Whether the gateway has paired devices, set by the process that runs it. They reach the host
    /// only while it runs, so a development host with any never stops for being idle.
    public var hasPairedDevices = false
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
        try store.pruneActivity(.commandRun, olderThan: .now.addingTimeInterval(-30 * 24 * 3600))
    }

    /// Picks up what the previous run left unfinished, then keeps a heartbeat.
    public func start() {
        // Before recovery: the sessions it reloads get the tools' address.
        tasks.start()
        resolveNotificationsOfPreviousRun()
        resumeTitles()
        do {
            try resumeInterruptedWork()
        } catch {
            logger.error("Couldn't read what to recover: \(error.localizedDescription)")
        }
        startUpdates()
        startHostStatus()
        unloadIdleSessionsPeriodically()
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
            channel: configuration.location.channel, notificationEvents: true
        )
    }

    private func beat() {
        try? store.setMeta(MetaKey.heartbeat, String(Date.now.timeIntervalSince1970))
        restartIfReplacedOnDisk()
        guard let idleExit = configuration.idleExit else { return }
        let isBusy =
            !clients.isEmpty || hasPairedDevices || !stoppingSessions.isEmpty
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
        // At the pace the new specs' timeouts call for.
        unloadIdleSessionsPeriodically()
    }

    private func makeLink(_ spec: AgentSpec) -> AgentLink {
        let link = AgentLink(spec: spec)
        link.onChange = { [weak self, weak link] in
            guard let self, let link else { return }
            publishAgent(link)
        }
        refreshSavedCredentials(of: link)
        return link
    }

    /// The running agent for `agentID`, started if needed.
    func readyAgent(_ agentID: String) async throws -> AgentLink {
        guard let link = agents[agentID] else { throw HostError.unknownAgent(agentID) }
        let environment: @Sendable () async -> [String: String] = { [weak self] in
            await self?.launchEnvironment(of: agentID) ?? [:]
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

    /// Logs one of Native's own events for a session and sends it to the clients following it.
    func append(_ payload: HostEvent.Payload, to session: HostSession, at date: Date = .now) {
        send(session.append(payload, at: date), of: session)
        noteForNotifications(payload, in: session)
    }

    /// Logs an agent's update for a session and sends it to the clients following it.
    func append(_ update: AgentUpdate, to session: HostSession) {
        send(session.append(update), of: session)
    }

    private func send(_ event: LoggedEvent, of session: HostSession) {
        guard !session.subscribers.isEmpty else { return }
        let params = ClientLink.eventParams(event, of: session.id)
        for id in session.subscribers {
            clients[id]?.notify(HostProtocol.Method.sessionEvent, encodedParams: params)
        }
    }

    /// Tells every client the session's summary changed.
    func publish(_ session: HostSession) {
        let notification = SessionChangedNotification(summary: session.summary)
        for client in clients.values {
            client.notify(HostProtocol.Method.sessionChanged, notification)
        }
        tasks.sessionChanged(session)
        keepAwakeActivityChanged()
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
            subject: session.map { $0.displayTitle ?? $0.agentName }, detail: detail, recovery: recovery,
            previousRun: previousRun)
        guard let stored = try? store.appendActivity(entry) else { return }
        for client in clients.values {
            client.notify(HostProtocol.Method.activity, stored)
        }
    }
}
