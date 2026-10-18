import Foundation
import NativeHostProtocol

/// The host's door for paired devices: it pairs new ones through a window the Mac opens, admits
/// paired ones after a mutually authenticated Noise handshake, and hands each admitted connection
/// to the host as an ordinary client stream (filtered by `LinkMethodPolicy`). Off until the user
/// pairs a device: with nothing paired and no window open, nothing listens on the network.
///
/// The host plugs it in with a few lines (`docs/companion.md`, "Host integration"); the Mac app
/// drives it over `link.sock` beside the host's own socket (`LinkControlServer`).
public actor LinkGateway {
    public struct Configuration: Sendable {
        /// The gateway's folder inside the host's directory: key, devices and control socket.
        public var directory: URL
        public var hostID: HostID
        /// The machine's name, shown when pairing and advertised over Bonjour.
        public var machineName: String
        /// Lists 127.0.0.1 in the QR code, for development hosts and the simulator.
        public var includesLoopback: Bool
        public var preferredPort: UInt16
        public var pairingLifetime: Duration
        /// How long a device waits for the Mac's user before pairing gives up.
        public var confirmationTimeout: Duration
        /// Tests serve streams directly and open no listener.
        public var usesNetwork: Bool
        public var now: @Sendable () -> Date

        public init(
            directory: URL, hostID: HostID, machineName: String, includesLoopback: Bool = false,
            preferredPort: UInt16 = 47_118, pairingLifetime: Duration = .seconds(300),
            confirmationTimeout: Duration = .seconds(120), usesNetwork: Bool = true,
            now: @escaping @Sendable () -> Date = { Date() }
        ) {
            self.directory = directory
            self.hostID = hostID
            self.machineName = machineName
            self.includesLoopback = includesLoopback
            self.preferredPort = preferredPort
            self.pairingLifetime = pairingLifetime
            self.confirmationTimeout = confirmationTimeout
            self.usesNetwork = usesNetwork
            self.now = now
        }

        /// `<host directory>/Link`, where `LinkControlClient` finds the control socket too.
        public static func directory(inHostDirectory hostDirectory: URL) -> URL {
            hostDirectory.appending(path: "Link", directoryHint: .isDirectory)
        }

        var registryURL: URL { directory.appending(path: "devices.json") }
        var keyURL: URL { directory.appending(path: "identity.key") }
        public var controlSocketPath: String { directory.appending(path: "link.sock").path(percentEncoded: false) }
    }

    enum PairingDecision: Sendable {
        case accepted, rejected, expired
    }

    public nonisolated let configuration: Configuration
    let identity: LinkIdentity
    var registry: LinkDeviceRegistry
    var window: PairingWindow?
    var decision: CheckedContinuation<PairingDecision, Never>?
    /// Live connections per device, closed when it's revoked.
    var connections: [UUID: [ObjectIdentifier: SecureChannel]] = [:]
    var listener: LinkListener?
    var listenerStatus = LinkListenerStatus(state: .off)
    private var observers: [UUID: @Sendable (LinkStatus) -> Void] = [:]
    private var control: LinkControlServer?
    let accept: @Sendable (any ByteStream) -> Void
    let logger = HostLogger(category: "LinkGateway")

    /// `accept` gets each admitted device's stream; the host serves it like a local client.
    public init(
        configuration: Configuration, keyStore: (any LinkKeyStore)? = nil,
        accept: @escaping @Sendable (any ByteStream) -> Void
    ) throws {
        try FileManager.default.createDirectory(
            at: configuration.directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        self.configuration = configuration
        identity = try (keyStore ?? FileKeyStore(url: configuration.keyURL)).identity()
        registry = LinkDeviceRegistry.load(from: configuration.registryURL)
        self.accept = accept
    }

    /// Opens the control socket for the Mac app (`verifyPeer` adds a check beyond same-user, such
    /// as the host's code-signature verifier) and listens if there's anything to serve.
    public func start(verifyPeer: (@Sendable (Int32) throws -> Void)? = nil) throws {
        control = try LinkControlServer(path: configuration.controlSocketPath, gateway: self, verifyPeer: verifyPeer)
        updateListener()
    }

    public func stop() {
        control?.stop()
        control = nil
        listener?.cancel()
        listener = nil
        for channel in connections.values.flatMap(\.values) { channel.close() }
    }

    // MARK: - Status

    public var status: LinkStatus {
        let port = listenerStatus.port ?? registry.port ?? configuration.preferredPort
        var addresses = [LinkAddress(kind: .bonjour, host: configuration.machineName)]
        if configuration.usesNetwork {
            addresses += LinkInterfaces.addresses(port: port, includingLoopback: configuration.includesLoopback)
        }
        return LinkStatus(
            isEnabled: registry.isEnabled,
            listener: listenerStatus,
            hostName: configuration.machineName,
            hostKey: identity.publicKey,
            addresses: addresses,
            devices: registry.devices.map { LinkDeviceStatus(device: $0, isConnected: !(connections[$0.id] ?? [:]).isEmpty) },
            pairing: window.map { window in
                LinkPairingStatus(
                    invite: window.invite(
                        hostID: configuration.hostID, hostKey: identity.publicKey, hostName: configuration.machineName,
                        addresses: addresses),
                    code: window.code.rawValue, expiresAt: window.expiresAt, phase: window.phase,
                    request: window.request, pairedDeviceID: window.pairedDeviceID,
                    failedAttempts: window.failedAttempts)
            }
        )
    }

    /// Calls `handler` with every new status until `removeObserver`.
    public func observe(_ handler: @escaping @Sendable (LinkStatus) -> Void) -> UUID {
        let id = UUID()
        observers[id] = handler
        return id
    }

    public func removeObserver(_ id: UUID) {
        observers[id] = nil
    }

    func publish() {
        let status = status
        for observer in observers.values { observer(status) }
    }

    // MARK: - What the Mac's user does

    /// Opens a fresh pairing window (or replaces the current one), turning the gateway on.
    @discardableResult
    public func openPairingWindow() -> LinkStatus {
        resolveDecision(.rejected)
        window = PairingWindow(lifetime: configuration.pairingLifetime, now: configuration.now())
        if !registry.isEnabled {
            registry.isEnabled = true
            save()
        }
        updateListener()
        publish()
        return status
    }

    /// The sheet closed: a device still waiting is turned down.
    public func closePairingWindow() {
        resolveDecision(.rejected)
        window = nil
        updateListener()
        publish()
    }

    public func decidePairing(accept: Bool) {
        resolveDecision(accept ? .accepted : .rejected)
    }

    public func revoke(_ id: UUID) {
        registry.update(id) { $0.revokedAt = configuration.now() }
        save()
        for channel in (connections.removeValue(forKey: id) ?? [:]).values { channel.close() }
        updateListener()
        publish()
    }

    /// Undoes `revoke`.
    public func restore(_ id: UUID) {
        registry.update(id) { $0.revokedAt = nil }
        save()
        updateListener()
        publish()
    }

    /// Removes revoked devices for good.
    public func forgetRevoked() {
        registry.devices.removeAll(where: \.isRevoked)
        save()
        publish()
    }

    public func rename(_ id: UUID, to name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        registry.update(id) { $0.name = trimmed }
        save()
        publish()
    }

    /// Takes effect from the device's next connection.
    public func setRole(_ id: UUID, to role: LinkDeviceRole) {
        registry.update(id) { $0.role = role }
        save()
        for channel in (connections.removeValue(forKey: id) ?? [:]).values { channel.close() }
        publish()
    }

    /// Off stops listening and drops every paired connection; devices stay paired.
    public func setEnabled(_ isEnabled: Bool) {
        registry.isEnabled = isEnabled
        save()
        if !isEnabled {
            closePairingWindow()
            for channel in connections.values.flatMap(\.values) { channel.close() }
            connections = [:]
        }
        updateListener()
        publish()
    }

    func resolveDecision(_ value: PairingDecision) {
        decision?.resume(returning: value)
        decision = nil
    }

    func save() {
        do {
            try registry.save(to: configuration.registryURL)
        } catch {
            logger.error("Couldn't save paired devices: \(error.localizedDescription)")
        }
    }
}
