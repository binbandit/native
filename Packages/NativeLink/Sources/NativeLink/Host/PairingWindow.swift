import Foundation
import NativeHostProtocol

/// One open "Pair iPhone" sheet on the Mac, or one run of `pair` on a host without a screen: a QR
/// secret and a typed code, both single use, both gone when it expires. At most one device at a
/// time gets as far as asking the Mac's user.
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
    /// Set when whoever opened the window decided in advance (`pair` over SSH, where nobody sits at
    /// the host): the device that proves the invite's secret is paired with at most these grants,
    /// without asking. Only the invite pairs then: the typed code doesn't pin the host's key and
    /// needs someone to compare verification codes.
    let preapprovedGrants: LinkGrants?

    init(lifetime: Duration, now: Date, preapprovedGrants: LinkGrants? = nil) {
        var generator = SystemRandomNumberGenerator()
        secret = Data((0..<32).map { _ in UInt8.random(in: .min ... .max, using: &generator) })
        code = PairingCode()
        expiresAt = now.addingTimeInterval(TimeInterval(lifetime.components.seconds))
        self.preapprovedGrants = preapprovedGrants
    }

    /// The pre-shared key a device in `mode` must prove, or why it can't try.
    func preSharedKey(for mode: LinkHello.Mode, now: Date) throws(LinkRefusal) -> Data {
        guard phase == .open, now < expiresAt else {
            throw phase == .confirming ? .busy : phase == .tooManyAttempts ? .tooManyAttempts : .noPairingWindow
        }
        switch mode {
        case .pairWithInvite: return PairingInvite.preSharedKey(secret: secret)
        case .pairWithCode:
            guard preapprovedGrants == nil else { throw .noPairingWindow }
            return code.preSharedKey
        case .connect: throw .unknown
        }
    }

    func invite(hostID: HostID, hostKey: LinkPublicKey, hostName: String, addresses: [LinkAddress]) -> PairingInvite {
        PairingInvite(
            hostID: hostID, hostKey: hostKey, secret: secret, hostName: hostName, expiresAt: expiresAt,
            addresses: addresses, grants: preapprovedGrants)
    }

    /// Counts a wrong secret or code; the third closes the window.
    mutating func recordFailure() -> LinkRefusal {
        failedAttempts += 1
        guard failedAttempts >= Self.maximumAttempts else { return .wrongCode }
        phase = .tooManyAttempts
        return .tooManyAttempts
    }
}
