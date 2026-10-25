import ACP
import Foundation
import NativeHostClient
import NativeHostProtocol
import Observation
import os

/// The app's handle on its local Native host (`docs/durability.md`): it decides at launch where
/// this run's agents live, keeps that host up and connected, says how the connection is doing, and
/// tells the user what agents did while Native was closed. One per app, shared through the
/// environment; `AppModel` runs its sessions on the client `launch` returns.
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
    private(set) var placement = HostPlacement.pending
    private(set) var connection: NativeHostClient.ConnectionState?
    /// The sessions the host runs, kept current from its events, for counts.
    private(set) var sessions: [HostSessionSummary] = []
    /// The host process changed under a live connection, for a short while (`DurableHost+Activity`).
    var restart: HostRestart?
    /// The host has been out of reach long enough to say so, rather than a blip while it restarts.
    private(set) var isUnavailable = false
    /// What agents did while Native was closed ("while you were away"), until dismissed.
    var away: AwaySummary?
    /// How this app and its host compare, for `HostVersionNotice`, which names the two with
    /// `appVersionLabel` and the status's host version.
    var versionStatus = HostVersionStatus.matched
    var appVersionLabel = AppVersion.current.version
    /// The fallback notice the user dismissed, so it shows once (`HostFallback.noticeKey`).
    private(set) var dismissedFallback = UserDefaults.standard.string(forKey: DurableHost.dismissedFallbackKey)
    var errorMessage: String?

    @ObservationIgnored let registrar = HostRegistration()
    @ObservationIgnored var client: NativeHostClient?
    #if os(macOS)
    @ObservationIgnored private var attached: AttachedHost?
    /// When the attached host was last started, so one that keeps dying isn't restarted in a loop.
    @ObservationIgnored private var attachedStarts: [Date] = []
    #endif
    @ObservationIgnored private var lastEpoch: UUID?
    @ObservationIgnored private var unavailableTimer: Task<Void, Never>?
    /// Native's updater, whose status the host serves to paired devices as this Mac's.
    @ObservationIgnored weak var updates: UpdateController?
    @ObservationIgnored var reporting: Task<Void, Never>?
    /// The host process (its epoch) already asked to restart onto this app's binary.
    @ObservationIgnored var restartRequested: UUID?
    /// Set by Quit Native and Stop Agents, so quitting stops the host too.
    @ObservationIgnored var stopsAgentsOnQuit = false

    static let logger = Logger(subsystem: "Native", category: "DurableHost")
    private static let dismissedFallbackKey = "NativeHostFallbackNoticeDismissed"
    /// How long launch waits for a host before trying the next way, then running agents in the app.
    private static let quickConnect = Duration.seconds(2)
    private static let startTimeout = Duration.seconds(8)
    /// How long the host may be out of reach before Native says so: longer than launchd takes to
    /// restart a crashed host, so a crash reads as reconnecting, then back.
    private static let unavailableAfter = Duration.seconds(15)

    var location: HostLocation {
        registrar.location
    }

    /// The fallback notice to show now, if any: once per kind of fallback.
    var fallbackNotice: HostFallback? {
        guard let fallback = placement.fallback, fallback.noticeKey != dismissedFallback else { return nil }
        return fallback
    }

    /// Whether the user keeps agents running when Native quits (Settings ▸ Background).
    var isEnabled: Bool {
        HostSessions.isEnabled
    }

    /// Tasks running in the host right now.
    var workingTasks: Int {
        sessions.count(where: \.isWorking)
    }

    // MARK: - Launch

    /// Decides where this run's agents live and connects to their host: the background host when
    /// the user keeps agents running after quit (`HostSessions`), else a host Native starts and
    /// stops with itself, else nothing. Returns the connected client for
    /// `AppModel.connectHost(client:)`, or nil to run agents in the app as before.
    func launch() async -> NativeHostClient? {
        guard HostSessions.isEnabled else {
            placement = .inApp
            // It doesn't hold up the app's own agents.
            Task { await retireHost() }
            return nil
        }
        let fallback: HostFallback
        do {
            try await registrar.register()
            registration = .enabled
            if let client = await connect(within: Self.quickConnect) {
                return use(client, placement: .background)
            }
            // A login item that was stopped on purpose only starts again when registered afresh. One
            // that holds its lock is running, just slow to answer (busy, or still starting):
            // registering it afresh would stop it and its agents, so it gets longer instead.
            if !location.isHostRunning {
                try await registrar.restart()
            }
            if let client = await connect(within: Self.startTimeout) {
                return use(client, placement: .background)
            }
            fallback = .didNotStart(connectionProblem)
        } catch {
            if registrar.status == .needsApproval {
                registration = .needsApproval
                fallback = .backgroundNotAllowed
            } else {
                registration = .failed(error.localizedDescription)
                fallback = .registrationFailed(error.localizedDescription)
            }
        }
        await disconnect()
        #if os(macOS)
        if startAttached(), let client = await connect(within: Self.startTimeout) {
            return use(client, placement: .attached(fallback))
        }
        attached?.terminate()
        attached = nil
        await disconnect()
        #endif
        placement = .inAppFallback(fallback)
        return nil
    }

    private func use(_ client: NativeHostClient, placement: HostPlacement) -> NativeHostClient {
        self.placement = placement
        if placement == .background, dismissedFallback != nil {
            // Back in the background: a fallback later is news again.
            rememberDismissedFallback(nil)
        }
        return client
    }

    /// Why the last connection attempt failed, in the client's words.
    private var connectionProblem: String {
        switch connection {
        case .reconnecting(_, let reason), .unreachable(let reason): reason
        case .incompatible(_, let host): "The host is from Native \(host.version)."
        default: "The host didn't answer."
        }
    }

    /// Connects to this channel's socket and waits for the handshake, giving up (but leaving the
    /// client trying) after `timeout`. Reuses the client across attempts. A host from another
    /// version counts as there: it's moved onto this app's binary as `HostVersionNotice` says,
    /// never replaced or bypassed, since it may be running tasks.
    private func connect(within timeout: Duration) async -> NativeHostClient? {
        let client = self.client ?? makeClient()
        let connected = await withTaskGroup(of: Bool.self) { group in
            group.addTask {
                while !Task.isCancelled {
                    switch await client.state {
                    case .connected, .incompatible: return true
                    case .connecting, .reconnecting, .unreachable: try? await Task.sleep(for: .milliseconds(50))
                    }
                }
                return false
            }
            group.addTask {
                try? await Task.sleep(for: timeout)
                return false
            }
            let first = await group.next() ?? false
            group.cancelAll()
            return first
        }
        return connected ? client : nil
    }

    private func makeClient() -> NativeHostClient {
        let info = Bundle.main.infoDictionary ?? [:]
        let client = NativeHostClient(
            transport: LocalSocketTransport(location: registrar.location),
            clientInfo: PeerInfo(
                name: "Native", version: info["CFBundleShortVersionString"] as? String ?? "0",
                build: info["CFBundleVersion"] as? String ?? "0")
        )
        self.client = client
        let receive: NativeHostClient.EventHandler = { [weak self] event in await self?.receive(event) }
        Task {
            await client.addEventHandler(receive)
            await client.start()
        }
        return client
    }

    func disconnect() async {
        await client?.stop()
        client = nil
        connection = nil
        sessions = []
    }

    /// With background agents off, a host left from when they were on stops, with its agents, so
    /// nothing keeps running that the user turned off and no conversation runs twice.
    private func retireHost() async {
        guard FileManager.default.fileExists(atPath: location.socketPath) else { return }
        if let client = await connect(within: .seconds(1)) {
            try? await client.shutdownHost(stopAgents: true)
        }
        await disconnect()
        try? await registrar.unregister()
        // Nothing listens on it now; without it the next launch has nothing to retire.
        try? FileManager.default.removeItem(atPath: location.socketPath)
    }

    #if os(macOS)
    /// Starts a host as Native's own child, which stops its agents when Native quits.
    private func startAttached() -> Bool {
        attachedStarts = attachedStarts.filter { $0.timeIntervalSinceNow > -60 } + [.now]
        do {
            attached = try AttachedHost.start(appBundle: Bundle.main.bundleURL, location: location)
            return true
        } catch {
            errorMessage = "Couldn't start Native's host: \(error.localizedDescription)"
            return false
        }
    }
    #endif

    // MARK: - Staying connected

    private func receive(_ event: NativeHostClient.Event) {
        switch event {
        case .connection(let state):
            connectionChanged(to: state)
        case .sessionChanged(let summary):
            upsert(summary)
            refreshVersionStatus()
        case .sessionClosed(let session):
            sessions.removeAll { $0.id == session }
        case .activity(let entry):
            noteSeen(entry)
        case .appUpdateCheckRequested:
            updates?.checkForUpdates()
        case .appUpdateInstallRequested(let when):
            // A device asked; `.now` only after its user chose to interrupt running tasks.
            updates?.installForRemote(when == .now ? .now : .whenTasksFinish)
        case .sessionEvent, .pluginsChanged, .updateChanged, .agentChanged, .notificationPosted,
            .notificationsCleared:
            // Sessions, plugins, agents and notifications reach the app through `AppModel` and its
            // features, and its updater is the source of the update status it would hear back.
            break
        }
    }

    private func connectionChanged(to state: NativeHostClient.ConnectionState) {
        connection = state
        switch state {
        case .connected(let info):
            unavailableTimer?.cancel()
            isUnavailable = false
            let reconnection: Reconnection =
                switch lastEpoch {
                case nil: .launch
                case info.epoch: .sameHost
                default: .newHost
                }
            lastEpoch = info.epoch
            // Handlers mustn't wait on requests to the client that called them.
            Task { await connected(info, reconnection: reconnection) }
        case .reconnecting:
            keepHostUp()
        case .unreachable:
            keepHostUp()
            guard unavailableTimer == nil else { return }
            unavailableTimer = Task { [weak self] in
                try? await Task.sleep(for: Self.unavailableAfter)
                guard !Task.isCancelled, let self else { return }
                self.unavailableTimer = nil
                if case .unreachable = self.connection { self.isUnavailable = true }
            }
        case .incompatible(let protocolVersion, let host):
            // The client already asked an older host to restart once idle.
            let labels = Self.versionLabels(host: host)
            appVersionLabel = labels.app
            versionStatus =
                protocolVersion < HostProtocol.version
                ? .hostRestartPending(hostVersion: labels.host, workingTasks: 0)
                : .appOutdated(hostVersion: labels.host)
        case .connecting:
            break
        }
    }

    private func connected(_ info: HostInfo, reconnection: Reconnection) async {
        // A host being retired (background agents turned off) has nothing to say to this run.
        guard let client, placement != .inApp else { return }
        do {
            // `AppModel` syncs the agents it launches with; this only keeps count.
            sessions = try await client.sessions().filter { $0.origin != .announced }
            refreshVersionStatus()
        } catch {
            Self.logger.error("Couldn't list the host's sessions: \(error.localizedDescription, privacy: .public)")
        }
        await readActivity(from: client, host: info, reconnection: reconnection)
        // A new host process hasn't heard the updater's status yet.
        if let updates {
            await report(updates.snapshot)
        }
    }

    /// A host that went away is brought back the way it runs: launchd restarts a background host
    /// by itself, unless the user just switched Native off under Allow in the Background, in which
    /// case Native runs one of its own; an attached host is Native's to restart.
    private func keepHostUp() {
        #if os(macOS)
        switch placement {
        case .background where !registrar.isDevelopmentBuild && registrar.status == .needsApproval:
            registration = .needsApproval
            if startAttached() { placement = .attached(.backgroundNotAllowed) }
        case .attached:
            guard attached?.isRunning == false, attachedStarts.count(where: { $0.timeIntervalSinceNow > -60 }) < 3
            else { return }
            _ = startAttached()
        default:
            break
        }
        #endif
    }

    /// Starts the host again after it stopped answering: the user's Retry.
    func startHostAgain() async {
        unavailableTimer?.cancel()
        unavailableTimer = nil
        isUnavailable = false
        #if os(macOS)
        if case .attached = placement {
            attached?.terminate()
            attachedStarts = []
            _ = startAttached()
            return
        }
        #endif
        do {
            try await registrar.restart()
        } catch {
            errorMessage = "Couldn't start Native's background host: \(error.localizedDescription)"
        }
    }

    /// The user read the fallback notice; it shows again only for another kind of fallback.
    func dismissFallbackNotice() {
        rememberDismissedFallback(placement.fallback)
    }

    private func rememberDismissedFallback(_ fallback: HostFallback?) {
        dismissedFallback = fallback?.noticeKey
        UserDefaults.standard.set(dismissedFallback, forKey: Self.dismissedFallbackKey)
    }

    // MARK: - Sessions

    func upsert(_ summary: HostSessionSummary) {
        guard summary.origin != .announced else { return }
        if let index = sessions.firstIndex(where: { $0.id == summary.id }) {
            sessions[index] = summary
        } else {
            sessions.insert(summary, at: 0)
        }
    }

    func perform<Result>(_ action: String, _ body: (NativeHostClient) async throws -> Result) async {
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
