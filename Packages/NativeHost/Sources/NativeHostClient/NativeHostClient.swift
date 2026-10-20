import ACP
import Foundation
import NativeHostProtocol

/// A client of one Native host: the Mac app's connection to its local host, and later the iPad's
/// and iPhone's connection to a paired one. It keeps the connection up across host restarts and
/// network drops, re-attaching every session it follows so no event is missed or applied twice.
///
/// Everything the host says arrives in order: to each handler added with `addEventHandler`, awaited
/// one after another, and on `events`. Folding a session's steps with a `SessionMirror` gives its
/// transcript. Requests live in the `NativeHostClient+…` files.
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
        /// One of a followed session's events, its agent payload already decoded.
        case sessionEvent(HostSessionID, SessionMirror.Step)
        case sessionChanged(HostSessionSummary)
        case sessionClosed(HostSessionID)
        /// An agent's status changed.
        case agentChanged(HostAgent)
        case activity(ActivityEntry)
        /// The host's plugin catalog changed.
        case pluginsChanged([HostPlugin])
        /// The host's update status moved.
        case updateChanged(HostUpdateStatus)
        /// For the Mac app only: a device asked its host to check for or install an update, which
        /// Native.app's updater does.
        case appUpdateCheckRequested
        case appUpdateInstallRequested(HostUpdateStatus.When)
        /// Something the user may want to hear about (docs/durability.md, "Notifications").
        case notificationPosted(HostNotification)
        /// Notifications that stopped being news: take them down.
        case notificationsCleared(NotificationsClearedMessage)
    }

    /// Called for every event, in order. A response to a request returns only after every handler
    /// has finished with the events that arrived before it. A handler must never wait on a request
    /// to this client: the response can't be read until the handler returns.
    public typealias EventHandler = @Sendable (Event) async -> Void

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
    private var handlers: [(id: UUID, handle: EventHandler)] = []
    private var peer: JSONRPCPeer?
    private var generation = 0
    private var running: Task<Void, Never>?
    /// Sessions this client follows, with the last event seen, to re-attach without gaps.
    var attachments: [HostSessionID: Int?] = [:]
    private(set) var epoch: UUID?
    /// Notifications that aren't `Event`s (a remote command's output), by method, in order with
    /// everything else. See `HostNotificationRoute`.
    var notificationRoutes: [String: any HostNotificationRoute] = [:]

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

    /// Adds a handler for everything the host says from now on; see `EventHandler`.
    @discardableResult
    public func addEventHandler(_ handler: @escaping EventHandler) -> UUID {
        let id = UUID()
        handlers.append((id, handler))
        return id
    }

    public func removeEventHandler(_ id: UUID) {
        handlers.removeAll { $0.id == id }
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

    func call<Result: Decodable & Sendable>(
        _ method: String, _ params: some Encodable & Sendable
    ) async throws -> Result {
        guard let peer, hostInfo != nil || method == HostProtocol.Method.initialize else { throw Failure.notConnected }
        return try await peer.request(method, params, as: Result.self)
    }

    /// Whether `error` means the request may not have reached the host, so it's worth sending again
    /// once connected.
    static func isConnectionLoss(_ error: any Error) -> Bool {
        (error as? PeerError) == .closed || (error as? Failure) == .notConnected
    }

    // MARK: - Connection

    private func maintainConnection() async {
        var failures = 0
        while !Task.isCancelled {
            do {
                try await connectOnce()
                failures = 0
                await peer?.closed()
                await setState(.reconnecting(attempt: 0, reason: "The connection to the host closed."))
            } catch let error as VersionMismatch {
                await setState(
                    .incompatible(protocolVersion: error.handshake.protocolVersion, host: error.handshake.hostInfo))
                // Check again now and then: an older host comes back on the new binary once idle,
                // and the drop while it restarts reads as reconnecting, not unreachable.
                failures = 0
                try? await Task.sleep(for: .seconds(5))
            } catch {
                failures += 1
                let reason = error.localizedDescription
                await setState(
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
        await setState(.connected(info))
        for (session, seen) in attachments {
            _ = try? await peer.request(
                HostProtocol.Method.attach, AttachParams(sessionID: session, epoch: epoch, afterSeq: seen),
                as: AttachResult.self)
        }
    }

    private func receive(_ event: JSONRPCPeer.Event, generation: Int) async {
        guard generation == self.generation, case .notification(let message) = event else { return }
        if let route = notificationRoutes[message.method] {
            await route.receive(message)
            return
        }
        guard let event = Self.event(from: message) else { return }
        if case .sessionEvent(let session, let step) = event, attachments.keys.contains(session) {
            attachments[session] = step.event.seq
        }
        if case .sessionClosed(let session) = event {
            attachments[session] = nil
        }
        await deliver(event)
    }

    private func deliver(_ event: Event) async {
        for handler in handlers {
            await handler.handle(event)
        }
        continuation.yield(event)
    }

    /// The event a host notification stands for; nil for ones this client doesn't know.
    private static func event(from message: JSONRPCPeer.Message) -> Event? {
        typealias Method = HostProtocol.Method
        switch message.method {
        case Method.sessionEvent:
            return (try? message.params(as: StepNotification.self)).map { .sessionEvent($0.sessionID, $0.event) }
        case Method.sessionChanged:
            return (try? message.params(as: SessionChangedNotification.self)).map { .sessionChanged($0.summary) }
        case Method.sessionClosed:
            return (try? message.params(as: SessionParams.self)).map { .sessionClosed($0.sessionID) }
        case Method.agentChanged:
            return (try? message.params(as: AgentChangedNotification.self)).map { .agentChanged($0.agent) }
        case Method.activity:
            return (try? message.params(as: ActivityEntry.self)).map(Event.activity)
        case Method.updateChanged:
            return (try? message.params(as: HostUpdateStatusMessage.self)).map { .updateChanged($0.status) }
        case Method.appUpdateCheck:
            return .appUpdateCheckRequested
        case Method.appUpdateInstall:
            return (try? message.params(as: HostUpdateInstallParams.self)).map { .appUpdateInstallRequested($0.when) }
        case Method.pluginsChanged:
            return (try? message.params(as: PluginsChangedNotification.self)).map { .pluginsChanged($0.plugins) }
        case Method.notificationPosted:
            return (try? message.params(as: NotificationPostedMessage.self)).map {
                .notificationPosted($0.notification)
            }
        case Method.notificationsCleared:
            return (try? message.params(as: NotificationsClearedMessage.self)).map(Event.notificationsCleared)
        default:
            return nil
        }
    }

    private func setState(_ state: ConnectionState) async {
        guard state != self.state else { return }
        self.state = state
        await deliver(.connection(state))
    }

    /// A `SessionEventNotification` decoded straight into a step.
    private struct StepNotification: Decodable {
        var sessionID: HostSessionID
        var event: SessionMirror.Step
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
