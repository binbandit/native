import Foundation
import NativeHostProtocol

/// One way to reach a host. The QR code lists every address the host has, and a paired device keeps
/// them to try when Bonjour can't find the host.
public struct LinkAddress: Codable, Hashable, Sendable {
    public enum Kind: String, WireEnum {
        /// An IP address on a local network.
        case lan
        /// The host's Bonjour service name; resolved on the device's network.
        case bonjour
        /// A Tailscale (CGNAT range) address: reachable wherever the tailnet is.
        case tailnet
        /// This machine itself, for development hosts and the simulator.
        case loopback
        /// Reserved: a ciphertext-only relay (`docs/companion.md`, "Transport").
        case relay
        case unknown
    }

    public var kind: Kind
    public var host: String
    /// Nil for a Bonjour name, which resolves to its own port.
    public var port: UInt16?

    public init(kind: Kind, host: String, port: UInt16? = nil) {
        self.kind = kind
        self.host = host
        self.port = port
    }

    /// What a connection log or troubleshooting line calls it.
    public var label: String {
        switch kind {
        case .bonjour: "\(host) (Bonjour)"
        case .tailnet: "\(host):\(port ?? 0) (Tailscale)"
        case .loopback: "\(host):\(port ?? 0) (this Mac)"
        case .relay: "relay \(host)"
        case .lan, .unknown: "\(host):\(port ?? 0)"
        }
    }

    // Short keys keep the QR code small enough to scan from across a desk.
    private enum CodingKeys: String, CodingKey {
        case kind = "t"
        case host = "h"
        case port = "p"
    }
}
