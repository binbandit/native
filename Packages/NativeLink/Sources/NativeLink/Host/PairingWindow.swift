import Foundation
import NativeHostProtocol

/// One open "Pair iPhone" sheet on the Mac: a QR secret and a typed code, both single use, both
/// gone when it expires. At most one device at a time gets as far as asking the Mac's user.
struct PairingWindow: Sendable {
    static let maximumAttempts = 3

    let id = UUID()
    let secret: Data
    let code: PairingCode
    let expiresAt: Date
    var phase = LinkPairingStatus.Phase.open
    var request: LinkPairingRequest?
    var pairedDeviceID: UUID?
    var failedAttempts = 0

    init(lifetime: Duration, now: Date) {
        var generator = SystemRandomNumberGenerator()
        secret = Data((0..<32).map { _ in UInt8.random(in: .min ... .max, using: &generator) })
        code = PairingCode()
        expiresAt = now.addingTimeInterval(TimeInterval(lifetime.components.seconds))
    }

    /// The pre-shared key a device in `mode` must prove, or why it can't try.
    func preSharedKey(for mode: LinkHello.Mode, now: Date) throws(LinkRefusal) -> Data {
        guard phase == .open, now < expiresAt else {
            throw phase == .confirming ? .busy : phase == .tooManyAttempts ? .tooManyAttempts : .noPairingWindow
        }
        switch mode {
        case .pairWithInvite: return PairingInvite.preSharedKey(secret: secret)
        case .pairWithCode: return code.preSharedKey
        case .connect: throw .unknown
        }
    }

    func invite(hostID: HostID, hostKey: LinkPublicKey, hostName: String, addresses: [LinkAddress]) -> PairingInvite {
        PairingInvite(
            hostID: hostID, hostKey: hostKey, secret: secret, hostName: hostName, expiresAt: expiresAt,
            addresses: addresses)
    }

    /// Counts a wrong secret or code; the third closes the window.
    mutating func recordFailure() -> LinkRefusal {
        failedAttempts += 1
        guard failedAttempts >= Self.maximumAttempts else { return .wrongCode }
        phase = .tooManyAttempts
        return .tooManyAttempts
    }
}
