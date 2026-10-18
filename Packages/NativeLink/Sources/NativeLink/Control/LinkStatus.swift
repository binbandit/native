import Foundation
import NativeHostProtocol

/// Everything the Mac's Paired Devices page shows, as one snapshot the gateway pushes on every change.
public struct LinkStatus: Codable, Hashable, Sendable {
    public var isEnabled: Bool
    public var listener: LinkListenerStatus
    public var hostName: String
    public var hostKey: LinkPublicKey
    public var addresses: [LinkAddress]
    /// Revoked devices included, so revoking can be undone; the page shows the active ones.
    public var devices: [LinkDeviceStatus]
    public var pairing: LinkPairingStatus?

    public var activeDevices: [LinkDeviceStatus] {
        devices.filter { !$0.device.isRevoked }
    }
}

public struct LinkListenerStatus: Codable, Hashable, Sendable {
    public enum State: String, WireEnum {
        /// Nothing listens: the gateway is off, or there's nothing to serve yet.
        case off
        case starting
        case listening
        case failed
        case unknown
    }

    public var state: State
    public var port: UInt16?
    public var problem: String?

    public init(state: State, port: UInt16? = nil, problem: String? = nil) {
        self.state = state
        self.port = port
        self.problem = problem
    }
}

public struct LinkDeviceStatus: Codable, Hashable, Sendable, Identifiable {
    public var device: LinkDevice
    public var isConnected: Bool

    public var id: UUID { device.id }
}

/// The pairing window the sheet on the Mac shows: its QR invite and typed code, and how far it got.
public struct LinkPairingStatus: Codable, Hashable, Sendable {
    public enum Phase: String, WireEnum {
        /// Waiting for a device to scan or type the code.
        case open
        /// A device proved the code; the Mac's user decides.
        case confirming
        case paired
        case rejected
        /// The window ran out (or nobody confirmed in time).
        case expired
        /// Three wrong codes.
        case tooManyAttempts
        case unknown
    }

    public var invite: PairingInvite
    /// The typed code, upper-case base32 (`PairingCode.rawValue`).
    public var code: String
    public var expiresAt: Date
    public var phase: Phase
    public var request: LinkPairingRequest?
    public var pairedDeviceID: UUID?
    public var failedAttempts: Int

    public var displayCode: String {
        PairingCode(typed: code)?.description ?? code
    }
}

/// A device waiting for the Mac's user to trust it.
public struct LinkPairingRequest: Codable, Hashable, Sendable {
    public var device: LinkDeviceInfo
    public var verification: VerificationCode
    /// How it found the host: by scanning the QR code (the host's key was pinned from it) or by
    /// typing the code (the verification code is what proves nobody is in the middle).
    public var usedCode: Bool
}
