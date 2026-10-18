import Foundation

/// Why a link connection or pairing didn't go through, worded for the person holding the device.
public enum LinkError: Error, Equatable, Sendable, LocalizedError {
    /// The host refused before any keys existed (see `LinkRefusal`).
    case refused(LinkRefusal)
    /// The host's key isn't the one the QR code or the pairing pinned: possibly another machine.
    case hostKeyMismatch
    /// The host revoked this device.
    case revoked
    /// The host doesn't know this device (it was removed, or the host was reset).
    case unknownDevice
    /// Pairing: the Mac's user declined.
    case rejected
    /// Pairing: nobody confirmed on the Mac in time.
    case confirmationExpired
    /// The handshake failed authentication.
    case handshakeFailed
    /// The other end hung up.
    case closed
    case timedOut
    case malformed(String)

    public var errorDescription: String? {
        switch self {
        case .refused(let refusal): refusal.message
        case .hostKeyMismatch:
            "That Mac didn't prove it's the one you paired with, so nothing was sent. If you reset Native on it, pair again."
        case .revoked: "This device was removed on the Mac. Pair again to reconnect."
        case .unknownDevice: "The Mac doesn't know this device anymore. Pair again to reconnect."
        case .rejected: "The Mac declined the pairing."
        case .confirmationExpired: "Nobody confirmed on the Mac in time. Make a new code there and try again."
        case .handshakeFailed: "The secure connection couldn't be set up."
        case .closed: "The connection closed."
        case .timedOut: "The Mac didn't answer in time."
        case .malformed(let detail): "The Mac sent something unexpected (\(detail))."
        }
    }

    /// Whether trying again later can help, or the pairing itself is gone.
    public var endsPairing: Bool {
        self == .revoked || self == .unknownDevice
    }
}
