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
    static let setGrants = "link/devices/grants"
    static let forgetRevoked = "link/devices/forget_revoked"
    static let setEnabled = "link/enabled"

    /// Gateway → app notification.
    static let changed = "link/status/changed"
}

/// `link/pairing/open`. Absent from older apps, which always open a window their user confirms.
struct LinkOpenPairingParams: Codable, Sendable {
    var preapprovedGrants: LinkGrants?
}

struct LinkDecisionParams: Codable, Sendable {
    var accept: Bool
    var grants: LinkGrants?
}

struct LinkDeviceParams: Codable, Sendable {
    var deviceID: UUID
    var name: String?
    var grants: LinkGrants?
}

struct LinkEnabledParams: Codable, Sendable {
    var isEnabled: Bool
}

struct LinkStatusNotification: Codable, Sendable {
    var status: LinkStatus
}
