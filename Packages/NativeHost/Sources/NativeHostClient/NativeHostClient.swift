import ACP
import Foundation
import NativeHostProtocol

/// A client of one Native host: the Mac app's connection to its local host, and later the iPad's
/// and iPhone's connection to a paired one. It keeps the connection up across host restarts and
/// network drops, re-attaching every session it follows so no event is missed or applied twice.
///
/// Everything the host says arrives on `events`, in order. Folding a session's events with a
/// `SessionMirror` gives its transcript.
public actor NativeHostClient {
    public enum ConnectionState: Hashable, Sendable {
        case connecting
        case connected(HostInfo)
        /// The connection dropped; trying again.
        case reconnecting(attempt: Int, reason: String)
        /// Nothing answered for a while; still trying, less often.
        case unreachable(reason: String)
        /// The host speaks another protocol version. An older host has been asked to restart onto
        /// this app's binary once it's idle; a newer one means this app should update. `host` names
        /// the host's version and build.
        case incompatible(protocolVersion: Int, host: PeerInfo)
    }

    public enum Event: Sendable {
        case connection(ConnectionState)
        case sessionEvent(HostSessionID, HostEvent)
        case sessionChanged(HostSessionSummary)
        case sessionClosed(HostSessionID)
        case activity(ActivityEntry)
        /// The host's plugin catalog changed.
        case pluginsChanged([HostPlugin])
    }

    public enum Failure: Error, LocalizedError, Equatable {
        case notConnected

        public var errorDescription: String? {
            switch self {
            case .notConnected: "Native's host isn't connected right now."
            }
        }
    }

    public nonisolated let events: AsyncStream<Event>
    public private(set) var state = ConnectionState.connecting
    public let transport: any HostTransport

    private let clientInfo: PeerInfo
    private let continuation: AsyncStream<Event>.Continuation
    private var peer: JSONRPCPeer?
    private var generation = 0
    private var running: Task<Void, Never>?
    /// Sessions this client follows, with the last event seen, to re-attach without gaps.
    private var attachments: [HostSessionID: Int?] = [:]
    private var epoch: UUID?

    /// How long the host may stay unreachable before the state says so.
    private static let unreachableAfter = 4

    public init(transport: any HostTransport, clientInfo: PeerInfo) {
        self.transport = transport
        self.clientInfo = clientInfo
        (events, continuation) = AsyncStream.makeStream(of: Event.self)
    }

    /// Connects and stays connected until `stop()`.
    public func start() {
        guard running == nil else { return }
        running = Task { await maintainConnection() }
    }

    public func stop() {
        running?.cancel()
        running = nil
        peer?.close()
        continuation.finish()
    }

    public var hostInfo: HostInfo? {
        if case .connected(let info) = state { info } else { nil }
    }

    /// Returns once connected (or immediately if already).
    public func connected() async throws -> HostInfo {
        while !Task.isCancelled {
            if let hostInfo { return hostInfo }
            try await Task.sleep(for: .milliseconds(50))
        }
        throw CancellationError()
    }

    // MARK: - Requests

    public func syncAgents(_ agents: [AgentSpec]) async throws {
        let _: EmptyMessage = try await call(HostProtocol.Method.syncAgents, SyncAgentsParams(agents: agents))
    }

    public func sessions() async throws -> [HostSessionSummary] {
        try await call(HostProtocol.Method.listSessions, EmptyMessage())
    }

    public func newSession(_ params: NewSessionParams) async throws -> HostSessionSummary {
        try await call(HostProtocol.Method.newSession, params)
    }

    public func openSession(_ params: OpenSessionParams) async throws -> HostSessionSummary {
        try await call(HostProtocol.Method.openSession, params)
    }

    /// Follows a session: its log is replayed onto `events` before this returns, then live events
    /// follow. After a reconnect it's re-attached from where it left off.
    @discardableResult
    public func attach(_ session: HostSessionID) async throws -> HostSessionSummary {
        let seen = attachments[session] ?? nil
        attachments.updateValue(seen, forKey: session)
        let result: AttachResult = try await call(
            HostProtocol.Method.attach, AttachParams(sessionID: session, epoch: epoch, afterSeq: seen))
        return result.summary
    }

    public func detach(_ session: HostSessionID) async throws {
        attachments[session] = nil
        let _: EmptyMessage = try await call(HostProtocol.Method.detach, SessionParams(sessionID: session))
    }

    /// Sends a message. Retrying with the same `requestID` is safe: the host delivers it once.
    public func prompt(_ params: PromptParams) async throws -> PromptDelivery {
        let result: PromptResult = try await call(HostProtocol.Method.prompt, params)
        return result.delivery
    }

    public func cancel(_ session: HostSessionID) async throws {
        let _: EmptyMessage = try await call(HostProtocol.Method.cancel, SessionParams(sessionID: session))
    }

    public func respondPermission(_ params: RespondPermissionParams) async throws {
        let _: EmptyMessage = try await call(HostProtocol.Method.respondPermission, params)
    }

    public func setConfigOption(_ params: SetConfigOptionParams) async throws {
        let _: EmptyMessage = try await call(HostProtocol.Method.setConfigOption, params)
    }

    public func updateQueued(_ params: QueueItemParams) async throws {
        let _: EmptyMessage = try await call(HostProtocol.Method.updateQueued, params)
    }

    public func removeQueued(_ params: QueueItemParams) async throws {
        let _: EmptyMessage = try await call(HostProtocol.Method.removeQueued, params)
    }

    public func sendQueuedNow(_ params: QueueItemParams) async throws {
        let _: EmptyMessage = try await call(HostProtocol.Method.sendQueuedNow, params)
    }

    public func closeSession(_ session: HostSessionID) async throws {
        attachments[session] = nil
        let _: EmptyMessage = try await call(HostProtocol.Method.closeSession, SessionParams(sessionID: session))
    }

    /// What happened on the host since `after` (an activity id), for "while you were away".
    public func activity(after: Int64? = nil, limit: Int = 200) async throws -> [ActivityEntry] {
        try await call(HostProtocol.Method.listActivity, ListActivityParams(after: after, limit: limit))
    }

    /// Stops the host and its agents for good, or (`stopAgents: false`) restarts it once idle.
    // MARK: - Plugins

    /// The plugins installed on the host. `PluginAssets` fetches and caches their files.
    public func plugins() async throws -> [HostPlugin] {
        try await call(HostProtocol.Method.listPlugins, EmptyMessage())
    }

    /// Turns a plugin on or off for everyone using the host; paired devices need the grant.
    public func setPluginEnabled(_ pluginID: String, _ isEnabled: Bool) async throws -> [HostPlugin] {
        try await call(
            HostProtocol.Method.setPluginEnabled, SetPluginEnabledParams(pluginID: pluginID, isEnabled: isEnabled))
    }

    public func pluginAsset(_ params: PluginAssetParams) async throws -> PluginAsset {
        try await call(HostProtocol.Method.pluginAsset, params)
    }

    /// Stops the host and its agents (`stopAgents`), or restarts it onto the binary the app
    /// carries: once it's idle, or `immediately`, interrupting turns that then resume.
    public func shutdownHost(stopAgents: Bool, immediately: Bool = false) async throws {
        do {
            let _: EmptyMessage = try await call(
                HostProtocol.Method.shutdown, ShutdownParams(stopAgents: stopAgents, immediately: immediately))
        } catch PeerError.closed {
            // The host can exit before its answer gets out; that's the request working.
        }
    }

    private func call<Result: Decodable & Sendable>(
        _ method: String, _ params: some Encodable & Sendable
    ) async throws -> Result {
        guard let peer, hostInfo != nil || method == HostProtocol.Method.initialize else { throw Failure.notConnected }
        return try await peer.request(method, params, as: Result.self)
    }

    // MARK: - Connection

    private func maintainConnection() async {
        var failures = 0
        while !Task.isCancelled {
            do {
                try await connectOnce()
                failures = 0
                await peer?.closed()
                setState(.reconnecting(attempt: 0, reason: "The connection to the host closed."))
            } catch let error as VersionMismatch {
                setState(
                    .incompatible(protocolVersion: error.handshake.protocolVersion, host: error.handshake.hostInfo))
                // Check again now and then: an older host comes back on the new binary once idle,
                // and the drop while it restarts reads as reconnecting, not unreachable.
                failures = 0
                try? await Task.sleep(for: .seconds(5))
            } catch {
                failures += 1
                let reason = error.localizedDescription
                setState(
                    failures >= Self.unreachableAfter
                        ? .unreachable(reason: reason) : .reconnecting(attempt: failures, reason: reason))
            }
            peer = nil
            // Quick at first (a host restarting under launchd is back within seconds), then patient.
            let delay: Duration =
                switch failures {
                case 0: .milliseconds(100)
                case 1...3: .milliseconds(250 << failures)
                default: .seconds(5)
                }
            try? await Task.sleep(for: delay)
        }
    }

    private func connectOnce() async throws {
        let stream = try await transport.connect()
        generation += 1
        let generation = generation
        let peer = JSONRPCPeer(channel: stream, label: "host") { [weak self] event in
            await self?.receive(event, generation: generation)
        }
        self.peer = peer
        peer.start()
        // Only the frozen part of the answer is read until the versions are known to match.
        let answer = try await peer.request(
            HostProtocol.Method.initialize, InitializeParams(clientInfo: clientInfo), as: JSONValue.self)
        let handshake = try Self.decode(FrozenHandshake.self, from: answer)
        guard handshake.protocolVersion == HostProtocol.version else {
            if handshake.protocolVersion < HostProtocol.version {
                // An older host moves onto this app's binary once nothing is running.
                _ = try? await peer.request(
                    HostProtocol.Method.shutdown, ShutdownParams(stopAgents: false), as: JSONValue.self)
            }
            peer.close()
            throw VersionMismatch(handshake: handshake)
        }
        let info = try Self.decode(HostInfo.self, from: answer)
        if epoch != info.epoch {
            // A new host process: sequence numbers start over, so re-attach from the beginning.
            for session in attachments.keys {
                attachments.updateValue(nil, forKey: session)
            }
        }
        epoch = info.epoch
        setState(.connected(info))
        for (session, seen) in attachments {
            _ = try? await peer.request(
                HostProtocol.Method.attach, AttachParams(sessionID: session, epoch: epoch, afterSeq: seen),
                as: AttachResult.self)
        }
    }

    private func receive(_ event: JSONRPCPeer.Event, generation: Int) {
        guard generation == self.generation, case .notification(let message) = event else { return }
        typealias Method = HostProtocol.Method
        switch message.method {
        case Method.sessionEvent:
            guard let notification = try? message.params(as: SessionEventNotification.self) else { return }
            if attachments.keys.contains(notification.sessionID) {
                attachments[notification.sessionID] = notification.event.seq
            }
            continuation.yield(.sessionEvent(notification.sessionID, notification.event))
        case Method.sessionChanged:
            if let notification = try? message.params(as: SessionChangedNotification.self) {
                continuation.yield(.sessionChanged(notification.summary))
            }
        case Method.sessionClosed:
            if let notification = try? message.params(as: SessionParams.self) {
                attachments[notification.sessionID] = nil
                continuation.yield(.sessionClosed(notification.sessionID))
            }
        case Method.activity:
            if let entry = try? message.params(as: ActivityEntry.self) {
                continuation.yield(.activity(entry))
            }
        case Method.pluginsChanged:
            if let notification = try? message.params(as: PluginsChangedNotification.self) {
                continuation.yield(.pluginsChanged(notification.plugins))
            }
        default:
            break
        }
    }

    private func setState(_ state: ConnectionState) {
        guard state != self.state else { return }
        self.state = state
        continuation.yield(.connection(state))
    }

    private struct VersionMismatch: Error {
        var handshake: FrozenHandshake
    }

    private static func decode<Value: Decodable>(_ type: Value.Type, from json: JSONValue) throws -> Value {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        return try decoder.decode(type, from: JSONEncoder().encode(json))
    }
}
