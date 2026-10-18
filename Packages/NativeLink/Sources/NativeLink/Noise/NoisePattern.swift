import Foundation

/// A Noise handshake pattern: which keys each message carries and which Diffie-Hellman results it
/// mixes in. Native uses two (see `docs/companion.md`, "Security"):
///
/// - `XX` for every connection after pairing: both sides send their static keys and each checks
///   the other's against the one it pinned.
/// - `XXpsk3` for pairing: the same, with the one-time pairing secret mixed in at the last message,
///   so only a device that read the code on the Mac can finish it.
struct NoisePattern: Sendable, Hashable {
    enum Token: Sendable, Hashable {
        case e, s, ee, es, se, ss, psk
    }

    let name: String
    let messages: [[Token]]

    static let xx = NoisePattern(name: "XX", messages: [[.e], [.e, .ee, .s, .es], [.s, .se]])
    static let xxpsk3 = NoisePattern(name: "XXpsk3", messages: [[.e], [.e, .ee, .s, .es], [.s, .se, .psk]])

    var protocolName: String {
        "Noise_\(name)_25519_ChaChaPoly_SHA256"
    }

    var usesPreSharedKey: Bool {
        messages.contains { $0.contains(.psk) }
    }
}
