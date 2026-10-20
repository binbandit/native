import Foundation
import NativeHostProtocol

/// The Mac app's handle on its host's gateway: the Paired Devices page and the pairing sheet. It
/// connects to `link.sock` while something is showing, and reports `nil` status while the host (and
/// so the gateway) isn't running.
public actor LinkControlClient {
    public enum Event: Sendable {
        case status(LinkStatus)
        /// The gateway can't be reached: the background host is off or still starting.
        case unavailable(String)
    }

    public nonisolated let events: AsyncStream<Event>
    private let continuation: AsyncStream<Event>.Continuation
    private let socketPath: String
    private var peer: JSONRPCPeer?
    private var running: Task<Void, Never>?

    /// `hostDirectory` is the host location's directory; the gateway lives in its `Link` folder.
    public init(hostDirectory: URL) {
        socketPath =
            LinkGateway.Configuration(
                directory: LinkGateway.Configuration.directory(inHostDirectory: hostDirectory), hostID: HostID(),
                machineName: ""
            ).controlSocketPath
        (events, continuation) = AsyncStream.makeStream(of: Event.self)
    }

    /// Connects, and reconnects every second while the gateway is away, until `stop()`.
    public func start() {
        guard running == nil else { return }
        running = Task { await maintain() }
    }

    public func stop() {
        running?.cancel()
        running = nil
        peer?.close()
        peer = nil
        continuation.finish()
    }

    // MARK: - Requests

    @discardableResult public func refresh() async throws -> LinkStatus {
        try await call(LinkControlMethod.status, EmptyMessage())
    }

    /// `preapprovedGrants` pairs the device that proves the invite without asking (see
    /// `LinkGateway.openPairingWindow(preapproving:)`).
    @discardableResult public func openPairingWindow(
        preapproving preapprovedGrants: LinkGrants? = nil
    ) async throws
        -> LinkStatus
    {
        try await call(LinkControlMethod.openPairing, LinkOpenPairingParams(preapprovedGrants: preapprovedGrants))
    }

    @discardableResult public func closePairingWindow() async throws -> LinkStatus {
        try await call(LinkControlMethod.closePairing, EmptyMessage())
    }

    @discardableResult public func decidePairing(accept: Bool, grants: LinkGrants) async throws -> LinkStatus {
        try await call(LinkControlMethod.decidePairing, LinkDecisionParams(accept: accept, grants: grants))
    }

    @discardableResult public func revoke(_ deviceID: UUID) async throws -> LinkStatus {
        try await call(LinkControlMethod.revoke, LinkDeviceParams(deviceID: deviceID))
    }

    @discardableResult public func restore(_ deviceID: UUID) async throws -> LinkStatus {
        try await call(LinkControlMethod.restore, LinkDeviceParams(deviceID: deviceID))
    }

    @discardableResult public func forgetRevoked() async throws -> LinkStatus {
        try await call(LinkControlMethod.forgetRevoked, EmptyMessage())
    }

    @discardableResult public func rename(_ deviceID: UUID, to name: String) async throws -> LinkStatus {
        try await call(LinkControlMethod.rename, LinkDeviceParams(deviceID: deviceID, name: name))
    }

    @discardableResult public func setGrants(_ deviceID: UUID, to grants: LinkGrants) async throws -> LinkStatus {
        try await call(LinkControlMethod.setGrants, LinkDeviceParams(deviceID: deviceID, grants: grants))
    }

    @discardableResult public func setEnabled(_ isEnabled: Bool) async throws -> LinkStatus {
        try await call(LinkControlMethod.setEnabled, LinkEnabledParams(isEnabled: isEnabled))
    }

    public enum Failure: Error, LocalizedError {
        case notConnected

        public var errorDescription: String? {
            "Native's background host isn't running, so paired devices can't be managed right now."
        }
    }

    private func call(_ method: String, _ params: some Encodable & Sendable) async throws -> LinkStatus {
        guard let peer else { throw Failure.notConnected }
        let status = try await peer.request(method, params, as: LinkStatus.self)
        continuation.yield(.status(status))
        return status
    }

    // MARK: - Connection

    private func maintain() async {
        while !Task.isCancelled {
            do {
                let stream = ByteChannel.socket(try UnixSocket.connect(to: socketPath), label: "link-control")
                let continuation = continuation
                let peer = JSONRPCPeer(channel: stream, label: "link-control") { event in
                    guard case .notification(let message) = event, message.method == LinkControlMethod.changed,
                        let notification = try? message.params(as: LinkStatusNotification.self)
                    else { return }
                    continuation.yield(.status(notification.status))
                }
                self.peer = peer
                peer.start()
                try await refresh()
                await peer.closed()
                self.peer = nil
                continuation.yield(.unavailable("The connection to Native's background host closed."))
            } catch {
                peer = nil
                continuation.yield(.unavailable(error.localizedDescription))
            }
            try? await Task.sleep(for: .seconds(1))
        }
    }
}
