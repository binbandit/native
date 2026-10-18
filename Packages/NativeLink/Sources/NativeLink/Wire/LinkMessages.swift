import Foundation
import NativeHostProtocol

/// What a paired device may do beyond following and driving tasks, granted by the Mac's user when
/// they confirm the pairing (and changeable later). The gateway enforces them per method
/// (`LinkMethodPolicy`) and hands them to the host as its `ClientGrants`.
public struct LinkGrants: Codable, Hashable, Sendable {
    /// Turn the host's plugins on and off for everyone using it.
    public var managePlugins: Bool
    /// Install updates and restart the host. Offered on by default when the device scanned the QR
    /// code (the host's key was pinned from it), off when it typed the code.
    public var manageHost: Bool

    public init(managePlugins: Bool = false, manageHost: Bool = false) {
        self.managePlugins = managePlugins
        self.manageHost = manageHost
    }

    /// Following and driving tasks only.
    public static let standard = LinkGrants()

    /// What the Mac's confirmation offers before the user changes anything.
    public static func suggested(usedCode: Bool) -> LinkGrants {
        LinkGrants(managePlugins: false, manageHost: !usedCode)
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        managePlugins = try container.decodeIfPresent(Bool.self, forKey: .managePlugins) ?? false
        manageHost = try container.decodeIfPresent(Bool.self, forKey: .manageHost) ?? false
    }
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

    public init(name: String, model: String, system: String) {
        self.name = name
        self.model = model
        self.system = system
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
    var grants: LinkGrants?
    /// With `paired`: every address the host has, so a device that paired by code (and only knew
    /// the Bonjour name) can reach it off the local network too.
    var addresses: [LinkAddress]?
}
