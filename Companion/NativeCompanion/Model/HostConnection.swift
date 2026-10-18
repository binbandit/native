import ACP
import Foundation
import NativeHostClient
import NativeHostProtocol
import NativeLink
import Observation

/// One paired host on this phone: its own connection, sessions, transcripts, update state, plugins
/// and connection log. Nothing here is shared with another host (`docs/companion.md`, "Many hosts").
@Observable
final class HostConnection: Identifiable {
    let id: HostID
    private(set) var host: PairedHost
    var preferences: HostPreferences {
        didSet { preferences.save(for: id) }
    }
    private(set) var phase = HostConnectionPhase.connecting
    private(set) var sessions: [HostSessionSummary] = []
    private(set) var mirrors: [HostSessionID: SessionMirror] = [:]
    private(set) var log: [LinkLogEntry] = []
    private(set) var update: HostUpdateStatus?
    private(set) var plugins: [HostPlugin] = []
    /// When the session list last arrived from the host, for "Updated 3m ago".
    private(set) var lastSynced: Date?
    /// Permission answers given from this phone, by tool call, for "Allowed from iPhone".
    private(set) var answers: [String: String] = [:]

    @ObservationIgnored private var client: NativeHostClient?
    @ObservationIgnored private var listening: Task<Void, Never>?
    @ObservationIgnored private var attached: Set<HostSessionID> = []
    @ObservationIgnored private let discovered: @Sendable () -> [DiscoveredHost]
    /// Called when the host first reports an update it can install (for the local notification).
    @ObservationIgnored var onUpdateAvailable: ((HostConnection, HostUpdateStatus.Release) -> Void)?

    static let logLimit = 200

    init(host: PairedHost, discovered: @escaping @Sendable () -> [DiscoveredHost]) {
        id = host.hostID
        self.host = host
        self.discovered = discovered
        preferences = HostPreferences.load(for: host.hostID)
    }

    var name: String {
        let label = preferences.label?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return label.isEmpty ? host.machineName : label
    }

    /// For the actions extension; nil while disconnected.
    var activeClient: NativeHostClient? { client }

    // MARK: - Connection

    func start() {
        guard client == nil else { return }
        phase = .connecting
        record(LinkLogEntry(.info, "Connecting to \(host.machineName)"))
        let transport = PairingAwareTransport(
            inner: PairedHostTransport(
                host: host, device: CompanionDevice.info, discovered: discovered,
                log: { [weak self] entry in Task { @MainActor in self?.record(entry) } }),
            ended: { [weak self] error in Task { @MainActor in self?.pairingEnded(error) } })
        let client = NativeHostClient(transport: transport, clientInfo: CompanionDevice.peerInfo)
        self.client = client
        listening = Task { [weak self] in
            for await event in client.events {
                self?.handle(event)
            }
        }
        Task { await client.start() }
    }

    func stop() {
        listening?.cancel()
        listening = nil
        if let client {
            Task { await client.stop() }
        }
        client = nil
        attached = []
    }

    /// Starts over: after the Mac was asleep, or the person tapped Retry.
    func reconnect() {
        stop()
        start()
    }

    private func pairingEnded(_ error: LinkError) {
        record(LinkLogEntry(.failure, error.localizedDescription))
        stop()
        phase = .pairingEnded(error)
    }

    private func record(_ entry: LinkLogEntry) {
        log.append(entry)
        if log.count > Self.logLimit { log.removeFirst(log.count - Self.logLimit) }
    }

    private func handle(_ event: NativeHostClient.Event) {
        switch event {
        case .connection(let state):
            if case .pairingEnded = phase { return }
            phase = HostConnectionPhase(state)
            if case .connected(let info) = state {
                if host.machineName != info.machineName { host.machineName = info.machineName }
                Task { await refresh() }
            }
        case .sessionEvent(let sessionID, let event):
            mirrors[sessionID, default: SessionMirror()].apply(event)
        case .sessionChanged(let summary):
            upsert(summary)
            if summary.needsApproval || summary.isWorking { attach(summary.id) }
        case .sessionClosed(let sessionID):
            sessions.removeAll { $0.id == sessionID }
            mirrors[sessionID] = nil
            attached.remove(sessionID)
        case .updateChanged(let status):
            apply(status)
        case .pluginsChanged(let plugins):
            self.plugins = plugins
        case .activity, .appUpdateCheckRequested, .appUpdateInstallRequested:
            // The Mac app's business: the phone reads activity through the sessions themselves.
            break
        }
    }

    /// Everything the home screen needs after (re)connecting.
    func refresh() async {
        guard let client else { return }
        do {
            let list = try await client.sessions()
            sessions = list.filter { $0.origin != .announced }.sorted(by: Self.order)
            lastSynced = .now
            for session in sessions where session.needsApproval || session.isWorking {
                attach(session.id)
            }
        } catch {
            record(LinkLogEntry(.failure, "Couldn't list tasks: \(error.localizedDescription)"))
        }
        if let status = try? await client.updateStatus() { apply(status) }
        if let plugins = try? await client.plugins() { self.plugins = plugins }
    }

    private func upsert(_ summary: HostSessionSummary) {
        guard summary.origin != .announced else { return }
        if let index = sessions.firstIndex(where: { $0.id == summary.id }) {
            sessions[index] = summary
        } else {
            sessions.append(summary)
        }
        sessions.sort(by: Self.order)
        lastSynced = .now
    }

    private static func order(_ lhs: HostSessionSummary, _ rhs: HostSessionSummary) -> Bool {
        (lhs.lastActivity ?? .distantPast) > (rhs.lastActivity ?? .distantPast)
    }

    private func apply(_ status: HostUpdateStatus) {
        let hadUpdate = update?.hasInstallableUpdate ?? false
        update = status
        if !hadUpdate, status.hasInstallableUpdate, let release = status.available {
            onUpdateAvailable?(self, release)
        }
    }

    /// Follows a session so its transcript (and any approval it waits on) is live here.
    func attach(_ sessionID: HostSessionID) {
        guard let client, !attached.contains(sessionID) else { return }
        attached.insert(sessionID)
        Task {
            do {
                try await client.attach(sessionID)
            } catch {
                attached.remove(sessionID)
            }
        }
    }

    func summary(_ sessionID: HostSessionID) -> HostSessionSummary? {
        sessions.first { $0.id == sessionID }
    }

    func recordAnswer(_ text: String, toolCallID: String) {
        answers[toolCallID] = text
    }
}

/// Stops retrying once the host says this phone isn't paired anymore: another try can't change that.
private struct PairingAwareTransport: HostTransport {
    let inner: PairedHostTransport
    let ended: @Sendable (LinkError) -> Void

    var displayName: String { inner.displayName }

    func connect() async throws -> any ByteStream {
        do {
            return try await inner.connect()
        } catch let error as LinkError where error.endsPairing || error == .hostKeyMismatch {
            ended(error)
            throw error
        }
    }
}
