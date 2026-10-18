import Foundation

/// The Mac app's control of the gateway, JSON-RPC over `link.sock` in the gateway's folder (the
/// host's directory, readable by the user alone). Every request answers with the new `LinkStatus`,
/// and the gateway pushes `link/status` whenever anything changes.
enum LinkControlMethod {
    static let status = "link/status"
    static let openPairing = "link/pairing/open"
    static let closePairing = "link/pairing/close"
    static let decidePairing = "link/pairing/decide"
    static let revoke = "link/devices/revoke"
    static let restore = "link/devices/restore"
    static let rename = "link/devices/rename"
    static let setRole = "link/devices/role"
    static let forgetRevoked = "link/devices/forget_revoked"
    static let setEnabled = "link/enabled"

    /// Gateway → app notification.
    static let changed = "link/status/changed"
}

struct LinkDecisionParams: Codable, Sendable {
    var accept: Bool
}

struct LinkDeviceParams: Codable, Sendable {
    var deviceID: UUID
    var name: String?
    var role: LinkDeviceRole?
}

struct LinkEnabledParams: Codable, Sendable {
    var isEnabled: Bool
}

struct LinkStatusNotification: Codable, Sendable {
    var status: LinkStatus
}
