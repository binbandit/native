import ACP
import Foundation
import NativeHostClient
import NativeHostProtocol
import Observation

/// The app's handle on its local Native host: registering it with launchd, staying connected,
/// mirroring the sessions it runs, and moving the host onto this app's binary after an update. One
/// per app, shared through the environment. Phase 1 of `docs/durability.md` uses it for the Durable Sessions
/// preview; in Phase 2 `AppModel` and `SessionModel` sit on the same client.
///
/// Opt-in for now (`NativeHostEnabled`), so building Native doesn't register a launchd job for
/// every agent that runs it.
@Observable
final class DurableHost {
    enum Registration: Equatable {
        case off
        case enabled
        /// The user turned Native off under Login Items › Allow in the Background.
        case needsApproval
        case failed(String)
    }

    private(set) var registration = Registration.off
    private(set) var connection: NativeHostClient.ConnectionState?
    private(set) var sessions: [HostSessionSummary] = []
    private(set) var mirrors: [HostSessionID: SessionMirror] = [:]
    /// What happened while no client was looking, newest last ("while you were away").
    private(set) var awayActivity: [ActivityEntry] = []
    /// How this app and its host compare, for `HostVersionNotice`.
    private(set) var versionStatus = HostVersionStatus.matched
    var errorMessage: String?

    @ObservationIgnored private let registrar = HostRegistration()
    @ObservationIgnored private var client: NativeHostClient?
    @ObservationIgnored private var listening: Task<Void, Never>?
    @ObservationIgnored private var agents: [AgentSpec] = []
    @ObservationIgnored private var isStarted = false
    /// The host process (its epoch) already asked to restart onto this app's binary.
    @ObservationIgnored private var restartRequested: UUID?

    /// Per channel: every development build shares one defaults domain but has a host of its own, so
    /// turning one build's host on mustn't register the others'.
    private static let enabledKey = "NativeHostEnabled.\(HostRegistration().location.channel)"
    private static let seenActivityKey = "NativeHostSeenActivity.\(HostRegistration().location.channel)"

    private(set) var isEnabled = UserDefaults.standard.bool(forKey: DurableHost.enabledKey)

    var location: HostLocation {
        registrar.location
    }

    /// Connects if the host is enabled, registering it with launchd first.
    /// Connects if the host is enabled, with the agents plugins provide.
    func start(plugins agents: [AgentDefinition]) async {
        await start(agents: agents.map(AgentSpec.init))
    }

    /// Connects if the host is enabled. Calling it again only updates the agents.
    func start(agents: [AgentSpec]) async {
        self.agents = agents
        guard isEnabled, !isStarted else { return }
        isStarted = true
        await register()
        connect()
    }

    func setEnabled(_ enabled: Bool) async {
        UserDefaults.standard.set(enabled, forKey: Self.enabledKey)
        isEnabled = enabled
        if enabled {
            await register()
            connect()
        } else {
            await disconnect()
            do {
                try await registrar.unregister()
            } catch {
                errorMessage = "Couldn't unregister the host: \(error.localizedDescription)"
            }
            registration = .off
        }
    }

    // MARK: - Sessions

    /// Starts a session and returns its id, attached and ready to show.
    func newSession(agent: String, cwd: URL) async -> HostSessionID? {
        var created: HostSessionID?
        await perform("start a session") { client in
            let summary = try await client.newSession(
                NewSessionParams(agentID: agent, cwd: cwd.path(percentEncoded: false)))
            self.upsert(summary)
            self.mirrors[summary.id] = SessionMirror()
            try await client.attach(summary.id)
            created = summary.id
        }
        return created
    }

    func attach(_ session: HostSessionID) async {
        guard mirrors[session] == nil else { return }
        mirrors[session] = SessionMirror()
        await perform("open the session") { client in
            self.upsert(try await client.attach(session))
        }
    }

    /// Sends a message; it queues if a turn is running. The request id makes a retry after a dropped
    /// connection safe.
    func send(_ text: String, to session: HostSessionID) async {
        let params = PromptParams(sessionID: session, text: text)
        await perform("send the message") { client in
            _ = try await client.prompt(params)
        }
    }

    func cancel(_ session: HostSessionID) async {
        await perform("stop the turn") { client in try await client.cancel(session) }
    }

    func choose(_ option: PermissionOption, forToolCall toolCall: String, in session: HostSessionID) async {
        await perform("answer the request") { client in
            try await client.respondPermission(
                RespondPermissionParams(sessionID: session, toolCallID: toolCall, optionID: option.optionId))
        }
    }

    /// Stops the host and every agent it runs ("Quit Native and Stop Agents").
    func stopHost() async {
        await perform("stop the host") { client in try await client.shutdownHost(stopAgents: true) }
    }

    /// Restarts the host onto this app's binary now. Running turns are interrupted and resume on the
    /// new host, which says it restarted to update.
    func restartHost() async {
        await perform("restart the host") { client in
            try await client.shutdownHost(stopAgents: false, immediately: true)
        }
    }

    func dismissAwayActivity() {
        if let last = awayActivity.last {
            UserDefaults.standard.set(last.id, forKey: Self.seenActivityKey)
        }
        awayActivity = []
    }

    // MARK: - Connection

    private func register() async {
        do {
            try await registrar.register()
            registration = .enabled
        } catch {
            registration = registrar.status == .needsApproval ? .needsApproval : .failed(error.localizedDescription)
        }
    }

    private func connect() {
        guard client == nil else { return }
        let info = Bundle.main.infoDictionary ?? [:]
        let client = NativeHostClient(
            transport: LocalSocketTransport(location: registrar.location),
            clientInfo: PeerInfo(
                name: "Native", version: info["CFBundleShortVersionString"] as? String ?? "0",
                build: info["CFBundleVersion"] as? String ?? "0")
        )
        self.client = client
        listening = Task { [weak self] in
            for await event in client.events {
                await self?.receive(event)
            }
        }
        Task { await client.start() }
    }

    private func disconnect() async {
        listening?.cancel()
        await client?.stop()
        client = nil
        connection = nil
        sessions = []
        mirrors = [:]
    }

    private func receive(_ event: NativeHostClient.Event) async {
        switch event {
        case .connection(let state):
            connection = state
            switch state {
            case .connected:
                await connected()
                refreshVersionStatus()
            case .incompatible(let protocolVersion, let host):
                // The client already asked an older host to restart once idle.
                versionStatus =
                    protocolVersion < HostProtocol.version
                    ? .hostRestartPending(hostVersion: host.version, workingTasks: 0)
                    : .appOutdated(hostVersion: host.version)
            default:
                break
            }
        case .sessionEvent(let session, let event):
            mirrors[session]?.apply(event)
        case .sessionChanged(let summary):
            upsert(summary)
            refreshVersionStatus()
        case .sessionClosed(let session):
            sessions.removeAll { $0.id == session }
            mirrors[session] = nil
        case .pluginsChanged:
            // The app still reads its plugins from its own registry until Phase 2.
            break
        case .activity(let entry):
            // Seen as it happens, so it isn't news the next time the app connects.
            if awayActivity.isEmpty {
                UserDefaults.standard.set(entry.id, forKey: Self.seenActivityKey)
            }
        }
    }

    private func connected() async {
        guard let client else { return }
        do {
            try await client.syncAgents(agents)
            sessions = try await client.sessions().filter { $0.origin != .announced }
            let seen = UserDefaults.standard.object(forKey: Self.seenActivityKey) as? Int64
            let entries = try await client.activity(after: seen)
            if seen == nil {
                // The first connection only sets the baseline; there's no "away" before it.
                UserDefaults.standard.set(entries.last?.id ?? 0, forKey: Self.seenActivityKey)
            } else {
                // Each recovery is listed on its own, so the host's own restart adds nothing.
                awayActivity = entries.filter { $0.kind != .unknown && $0.kind != .hostStarted }
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Compares builds and, for a host from an earlier Native, asks it (once per host process) to
    /// restart onto this app's binary as soon as nothing is running.
    private func refreshVersionStatus() {
        guard case .connected(let info) = connection else { return }
        let appBuild = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "0"
        versionStatus = .compare(
            appBuild: appBuild, hostBuild: info.hostInfo.build, hostVersion: info.hostInfo.version,
            workingTasks: sessions.count(where: \.isWorking)
        )
        guard case .hostRestartPending = versionStatus, restartRequested != info.epoch, let client else { return }
        restartRequested = info.epoch
        Task { try? await client.shutdownHost(stopAgents: false) }
    }

    private func upsert(_ summary: HostSessionSummary) {
        guard summary.origin != .announced else { return }
        if let index = sessions.firstIndex(where: { $0.id == summary.id }) {
            sessions[index] = summary
        } else {
            sessions.insert(summary, at: 0)
        }
    }

    private func perform<Result>(_ action: String, _ body: (NativeHostClient) async throws -> Result) async {
        guard let client else {
            errorMessage = "Couldn't \(action): the host isn't connected."
            return
        }
        do {
            _ = try await body(client)
        } catch {
            errorMessage = "Couldn't \(action): \(error.localizedDescription)"
        }
    }
}
