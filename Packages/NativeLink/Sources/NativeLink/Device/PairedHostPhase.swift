import Foundation
import NativeHostClient
import NativeHostProtocol

/// A paired host's connection as a device shows it: the client's states, plus the one that ends a
/// pairing (revoked, forgotten, or a host that can't prove its key), which stops the retrying
/// instead of spinning forever. Every client of a paired host (the phone, a Mac) uses this.
public enum PairedHostPhase: Equatable, Sendable {
    case connecting
    case connected(HostInfo)
    case reconnecting(attempt: Int, reason: String)
    case unreachable(reason: String)
    case incompatible(protocolVersion: Int, host: PeerInfo)
    case pairingEnded(LinkError)

    public init(_ state: NativeHostClient.ConnectionState) {
        switch state {
        case .connecting: self = .connecting
        case .connected(let info): self = .connected(info)
        case .reconnecting(let attempt, let reason): self = .reconnecting(attempt: attempt, reason: reason)
        case .unreachable(let reason): self = .unreachable(reason: reason)
        case .incompatible(let version, let host): self = .incompatible(protocolVersion: version, host: host)
        }
    }

    public var isConnected: Bool {
        if case .connected = self { true } else { false }
    }

    public var hostInfo: HostInfo? {
        if case .connected(let info) = self { info } else { nil }
    }

    /// Whether the host is out of reach for long enough to say so: an unreachable host, or a
    /// pairing that ended. Reconnecting is a blip, not offline.
    public var isOffline: Bool {
        switch self {
        case .unreachable, .pairingEnded, .incompatible: true
        case .connecting, .connected, .reconnecting: false
        }
    }
}
