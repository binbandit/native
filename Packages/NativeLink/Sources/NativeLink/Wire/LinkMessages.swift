import Foundation
import NativeHostProtocol

/// What a paired device may do on its host. The gateway enforces it per method (`LinkMethodPolicy`).
public enum LinkDeviceRole: String, WireEnum, CaseIterable {
    /// The companion: follow and drive tasks (prompts, approvals, queue), see updates and plugins.
    case companion
    /// Everything `docs/durability.md` allows a paired device, including host settings, plugins,
    /// and (when they exist) commands and files: an iPad running the full app.
    case admin
    case unknown
}

/// The host's payload in the second handshake message, encrypted to the device.
struct LinkHostHello: Codable, Sendable {
    var hostID: HostID
    var name: String
    var linkVersion: Int
}

/// What a device says about itself in the last handshake message, encrypted to the host.
public struct LinkDeviceInfo: Codable, Hashable, Sendable {
    /// "Brayden's iPhone".
    public var name: String
    /// "iPhone", "iPad".
    public var model: String
    /// "iOS 27.1".
    public var system: String
    /// The role it asks for; the host grants it or less.
    public var role: LinkDeviceRole

    public init(name: String, model: String, system: String, role: LinkDeviceRole = .companion) {
        self.name = name
        self.model = model
        self.system = system
        self.role = role
    }
}

/// The host's first encrypted word after a handshake: whether the connection may go on, and why not.
struct LinkWelcome: Codable, Sendable {
    enum Status: String, WireEnum {
        /// A paired device: the host protocol follows.
        case ok
        /// Pairing: the device proved the secret and the Mac is asking its user. Another welcome follows.
        case awaitingConfirmation
        /// Pairing: the Mac's user said yes. The host protocol follows.
        case paired
        /// Pairing: the Mac's user said no.
        case rejected
        /// Pairing: nobody answered on the Mac before the window closed.
        case expired
        /// This device's key was revoked on the host.
        case revoked
        /// The host has never paired this key (or forgot it).
        case unknownDevice
        case unknown
    }

    var status: Status
    var deviceID: UUID?
    var verification: VerificationCode?
    var role: LinkDeviceRole?
}
