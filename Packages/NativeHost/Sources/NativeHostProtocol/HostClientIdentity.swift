import Foundation

/// Provenance supplied by an accepting transport, never by RPC parameters or `PeerInfo`.
/// A local uid identifies an account; a paired public key identifies a device, not its holder.
public struct HostClientIdentity: Codable, Hashable, Sendable {
    public enum Kind: String, Codable, Sendable {
        case unknown, localPeer, pairedDevice
    }

    public let kind: Kind
    public let localUID: UInt32?
    public let devicePublicKey: Data?

    private init(kind: Kind, localUID: UInt32? = nil, devicePublicKey: Data? = nil) {
        self.kind = kind
        self.localUID = localUID
        self.devicePublicKey = devicePublicKey
    }

    public static let unknown = HostClientIdentity(kind: .unknown)

    public static func localPeer(uid: UInt32) -> Self {
        Self(kind: .localPeer, localUID: uid)
    }

    public static func pairedDevice(publicKey: Data) -> Self {
        guard publicKey.count == 32 else { return .unknown }
        return Self(kind: .pairedDevice, devicePublicKey: publicKey)
    }
}
