import Foundation

/// A device paired with this host: its pinned key, what it said about itself, and what it may do.
public struct LinkDevice: Codable, Hashable, Sendable, Identifiable {
    public var id: UUID
    public var name: String
    public var model: String
    public var system: String
    public var publicKey: LinkPublicKey
    public var role: LinkDeviceRole
    public var pairedAt: Date
    public var lastSeen: Date?
    /// Set when revoked: the key is refused at the handshake, and the device is told so.
    public var revokedAt: Date?

    public var isRevoked: Bool { revokedAt != nil }

    public init(
        id: UUID = UUID(), info: LinkDeviceInfo, publicKey: LinkPublicKey, pairedAt: Date, role: LinkDeviceRole? = nil
    ) {
        self.id = id
        name = info.name
        model = info.model
        system = info.system
        self.publicKey = publicKey
        self.role = role ?? info.role
        self.pairedAt = pairedAt
    }
}

/// The host's paired devices and gateway settings, in one file beside its key (`devices.json`,
/// readable by the user alone). Revoked devices stay as tombstones so a revoked phone is told it was
/// removed, and so revoking can be undone.
struct LinkDeviceRegistry: Codable, Sendable {
    /// Whether paired devices may connect. Off by default; opening a pairing window turns it on.
    var isEnabled = false
    /// The port the listener last bound, kept so addresses a device saved stay right.
    var port: UInt16?
    var devices: [LinkDevice] = []

    var activeDevices: [LinkDevice] { devices.filter { !$0.isRevoked } }

    func device(withKey key: LinkPublicKey) -> LinkDevice? {
        devices.first { $0.publicKey == key }
    }

    /// Adds a device, replacing any earlier pairing of the same key (a phone pairing again).
    mutating func add(_ device: LinkDevice) {
        devices.removeAll { $0.publicKey == device.publicKey }
        devices.append(device)
    }

    mutating func update(_ id: UUID, _ change: (inout LinkDevice) -> Void) {
        guard let index = devices.firstIndex(where: { $0.id == id }) else { return }
        change(&devices[index])
    }

    static func load(from url: URL) -> LinkDeviceRegistry {
        guard let data = try? Data(contentsOf: url) else { return LinkDeviceRegistry() }
        return (try? Self.decoder.decode(LinkDeviceRegistry.self, from: data)) ?? LinkDeviceRegistry()
    }

    func save(to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(self)
        try data.write(to: url, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path(percentEncoded: false))
    }

    private static var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
