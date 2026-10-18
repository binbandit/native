import Foundation
import NativeHostClient
import NativeHostProtocol
import NativeLink

/// One host's connection as the phone shows it: the client's states, plus the two that end a
/// pairing (revoked, forgotten), which stop the retrying instead of spinning forever.
enum HostConnectionPhase: Equatable {
    case connecting
    case connected(HostInfo)
    case reconnecting(attempt: Int, reason: String)
    case unreachable(reason: String)
    case incompatible(protocolVersion: Int, host: PeerInfo)
    case pairingEnded(LinkError)

    init(_ state: NativeHostClient.ConnectionState) {
        switch state {
        case .connecting: self = .connecting
        case .connected(let info): self = .connected(info)
        case .reconnecting(let attempt, let reason): self = .reconnecting(attempt: attempt, reason: reason)
        case .unreachable(let reason): self = .unreachable(reason: reason)
        case .incompatible(let version, let host): self = .incompatible(protocolVersion: version, host: host)
        }
    }

    var isConnected: Bool {
        if case .connected = self { true } else { false }
    }

    /// One short line: "Connected", "Reconnecting…", "Not reachable".
    var title: String {
        switch self {
        case .connecting: "Connecting…"
        case .connected: "Connected"
        case .reconnecting(let attempt, _): attempt > 1 ? "Reconnecting (try \(attempt))…" : "Reconnecting…"
        case .unreachable: "Not reachable"
        case .incompatible: "Needs an update"
        case .pairingEnded(let error): error == .revoked ? "Removed on the Mac" : "No longer paired"
        }
    }

    /// Why, and what to do about it.
    func detail(hostName: String) -> String? {
        switch self {
        case .connecting, .connected: nil
        case .reconnecting(_, let reason): reason
        case .unreachable(let reason):
            "\(reason) Tasks keep running on \(hostName); this phone catches up when it reconnects."
        case .incompatible(let version, let host):
            version < HostProtocol.version
                ? "\(hostName) runs Native \(host.version), which is older than this app. Update Native on \(hostName)."
                : "\(hostName) runs Native \(host.version), which is newer than this app. Update this app."
        case .pairingEnded(let error): error.localizedDescription
        }
    }
}
