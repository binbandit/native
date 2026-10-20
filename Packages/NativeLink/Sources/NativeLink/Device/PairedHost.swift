import Foundation
import NativeHostProtocol

/// A host this device paired with, as the device keeps it. Every pairing has its own device key, so
/// no two hosts ever see the same key for this device and can't tell they share it. Keyed by the
/// host instance (`HostID`): two Natives on one Mac are two hosts.
public struct PairedHost: Codable, Hashable, Sendable, Identifiable {
    public var hostID: HostID
    public var hostKey: LinkPublicKey
    /// What the host calls itself (its machine name), kept current on each connection.
    public var machineName: String
    /// What the user named it on this device; the machine name until they do.
    public var label: String?
    public var addresses: [LinkAddress]
    /// The host's id for this device.
    public var deviceID: UUID
    public var grants: LinkGrants
    public var pairedAt: Date
    /// This device's private key for this host alone.
    public var deviceKey: Data
    /// What the user typed in Add Host to pair over SSH (`me@mac-mini.local`), for showing the
    /// exact `ssh` commands that reach the host. Nil for a pasted link, and in pairings saved before
    /// it existed (an optional, so synthesized decoding reads it with `decodeIfPresent`).
    public var sshDestination: String?

    public var id: HostID { hostID }

    public var displayName: String {
        guard let label, !label.trimmingCharacters(in: .whitespaces).isEmpty else { return machineName }
        return label
    }

    public init(result: LinkPairingResult, identity: LinkIdentity, pairedAt: Date = .now) {
        hostID = result.hostID
        hostKey = result.hostKey
        machineName = result.hostName
        addresses = result.addresses
        deviceID = result.deviceID
        grants = result.grants
        self.pairedAt = pairedAt
        deviceKey = identity.rawRepresentation
    }

    public func identity() throws -> LinkIdentity {
        try LinkIdentity(rawRepresentation: deviceKey)
    }
}
