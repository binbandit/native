import Foundation

/// The first frame a device sends, in the clear: the link protocol version and what it wants. It is
/// also the Noise prologue, so a changed hello breaks the handshake rather than going unnoticed.
struct LinkHello: Sendable, Equatable {
    enum Mode: UInt8, Sendable {
        /// A paired device connecting: `XX`, both static keys checked against the pinned ones.
        case connect = 0
        /// Pairing with the QR code's secret: `XXpsk3`.
        case pairWithInvite = 1
        /// Pairing with the typed code: `XXpsk3`, then the verification code on both screens.
        case pairWithCode = 2
    }

    static let magic = Data("NLNK".utf8)
    static let currentVersion: UInt8 = 1

    var version: UInt8 = Self.currentVersion
    var mode: Mode

    var bytes: Data {
        Self.magic + Data([version, mode.rawValue])
    }

    var pattern: NoisePattern {
        mode == .connect ? .xx : .xxpsk3
    }

    init(mode: Mode) {
        self.mode = mode
    }

    init(bytes: Data) throws {
        guard bytes.count == Self.magic.count + 2, bytes.prefix(Self.magic.count) == Self.magic else {
            throw LinkError.malformed("not a Native link hello")
        }
        let tail = Array(bytes.suffix(2))
        version = tail[0]
        guard version == Self.currentVersion else { throw LinkError.refused(.unsupportedVersion) }
        guard let mode = Mode(rawValue: tail[1]) else { throw LinkError.malformed("hello mode \(tail[1])") }
        self.mode = mode
    }
}

/// Why the host turned a connection away before any keys existed.
public enum LinkRefusal: UInt8, Sendable, Error, CaseIterable {
    /// The device speaks a link version this host doesn't.
    case unsupportedVersion = 1
    /// No pairing window is open: the sheet on the Mac was closed, the code expired, or it was used.
    case noPairingWindow = 2
    /// The secret or code didn't match the open pairing window.
    case wrongCode = 3
    /// Three wrong codes: the window is closed and the Mac needs a new code.
    case tooManyAttempts = 4
    /// Another device is waiting for the Mac to confirm it.
    case busy = 5
    case unknown = 255

    init(byte: UInt8?) {
        self = byte.flatMap(LinkRefusal.init(rawValue:)) ?? .unknown
    }

    /// What the device says, quoting the host: these arrive unauthenticated, so they guide rather than decide.
    public var message: String {
        switch self {
        case .unsupportedVersion:
            "That Mac runs a different version of Native. Update Native and this app, then try again."
        case .noPairingWindow:
            "The Mac isn't pairing right now. On your Mac, open Settings ▸ Paired Devices ▸ Pair iPhone and use the new code."
        case .wrongCode: "That code didn't match. Check the code on your Mac and try again."
        case .tooManyAttempts: "Too many wrong codes. Make a new code on your Mac."
        case .busy: "Another device is pairing with that Mac. Finish or cancel it there, then try again."
        case .unknown: "The Mac turned the connection away."
        }
    }
}
