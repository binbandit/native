import CryptoKit
import Foundation

/// One side of a Noise handshake (Curve25519, ChaChaPoly, SHA-256), driven message by message.
/// It does no I/O: the caller moves the bytes, so the same code runs over TCP, a relay later, or an
/// in-memory pipe in tests. Checked against the cacophony test vectors.
struct NoiseHandshake: Sendable {
    typealias PrivateKey = Curve25519.KeyAgreement.PrivateKey
    typealias PublicKey = Curve25519.KeyAgreement.PublicKey

    static let keyLength = 32

    let pattern: NoisePattern
    let isInitiator: Bool

    private var symmetric: NoiseSymmetricState
    private let localStatic: PrivateKey
    private var localEphemeral: PrivateKey?
    /// Tests fix the ephemeral key to reproduce the vectors; otherwise each handshake makes a fresh one.
    private let presetEphemeral: PrivateKey?
    private var remoteEphemeral: PublicKey?
    private(set) var remoteStatic: PublicKey?
    private let preSharedKey: Data?
    private var messageIndex = 0

    init(
        pattern: NoisePattern, isInitiator: Bool, prologue: Data, localStatic: PrivateKey,
        preSharedKey: Data? = nil, presetEphemeral: PrivateKey? = nil
    ) throws {
        if pattern.usesPreSharedKey {
            guard let preSharedKey, preSharedKey.count == Self.keyLength else {
                throw NoiseError.invalidPreSharedKey
            }
        }
        self.pattern = pattern
        self.isInitiator = isInitiator
        self.localStatic = localStatic
        self.preSharedKey = preSharedKey
        self.presetEphemeral = presetEphemeral
        symmetric = NoiseSymmetricState(protocolName: pattern.protocolName)
        symmetric.mixHash(prologue)
    }

    var isComplete: Bool { messageIndex == pattern.messages.count }

    /// Binds everything both sides said; equal on both ends once the handshake completes.
    var handshakeHash: Data { symmetric.hash }

    private var isOurTurn: Bool { (messageIndex % 2 == 0) == isInitiator }

    mutating func writeMessage(payload: Data = Data()) throws -> Data {
        guard !isComplete, isOurTurn else { throw NoiseError.outOfOrder }
        var message = Data()
        for token in pattern.messages[messageIndex] {
            switch token {
            case .e:
                let ephemeral = presetEphemeral ?? PrivateKey()
                localEphemeral = ephemeral
                let key = ephemeral.publicKey.rawRepresentation
                message += key
                mixEphemeral(key)
            case .s:
                message += try symmetric.encryptAndHash(localStatic.publicKey.rawRepresentation)
            default:
                try mix(token)
            }
        }
        message += try symmetric.encryptAndHash(payload)
        messageIndex += 1
        return message
    }

    mutating func readMessage(_ message: Data) throws -> Data {
        guard !isComplete, !isOurTurn else { throw NoiseError.outOfOrder }
        var rest = message[...]
        func take(_ count: Int) throws -> Data {
            guard rest.count >= count else { throw NoiseError.truncated }
            defer { rest = rest.dropFirst(count) }
            return Data(rest.prefix(count))
        }
        for token in pattern.messages[messageIndex] {
            switch token {
            case .e:
                let key = try take(Self.keyLength)
                remoteEphemeral = try Self.publicKey(key)
                mixEphemeral(key)
            case .s:
                let length = Self.keyLength + (symmetric.cipher.hasKey ? NoiseCipherState.tagLength : 0)
                remoteStatic = try Self.publicKey(try symmetric.decryptAndHash(try take(length)))
            default:
                try mix(token)
            }
        }
        let payload = try symmetric.decryptAndHash(Data(rest))
        messageIndex += 1
        return payload
    }

    /// The transport ciphers once the handshake is complete: one to send with, one to receive with.
    func split() throws -> (send: NoiseCipherState, receive: NoiseCipherState) {
        guard isComplete else { throw NoiseError.outOfOrder }
        let (first, second) = symmetric.split()
        return isInitiator ? (first, second) : (second, first)
    }

    private mutating func mixEphemeral(_ key: Data) {
        symmetric.mixHash(key)
        // PSK patterns also key the cipher from the ephemeral, so the PSK is never used with a fixed key.
        if pattern.usesPreSharedKey {
            symmetric.mixKey(key)
        }
    }

    /// The Diffie-Hellman and PSK tokens. `es` is always the initiator's ephemeral with the
    /// responder's static, whichever side computes it.
    private mutating func mix(_ token: NoisePattern.Token) throws {
        switch token {
        case .ee:
            symmetric.mixKey(try Self.agree(localEphemeral, remoteEphemeral))
        case .es:
            symmetric.mixKey(
                try isInitiator ? Self.agree(localEphemeral, remoteStatic) : Self.agree(localStatic, remoteEphemeral))
        case .se:
            symmetric.mixKey(
                try isInitiator ? Self.agree(localStatic, remoteEphemeral) : Self.agree(localEphemeral, remoteStatic))
        case .ss:
            symmetric.mixKey(try Self.agree(localStatic, remoteStatic))
        case .psk:
            guard let preSharedKey else { throw NoiseError.invalidPreSharedKey }
            symmetric.mixKeyAndHash(preSharedKey)
        case .e, .s:
            break
        }
    }

    private static func agree(_ privateKey: PrivateKey?, _ publicKey: PublicKey?) throws -> Data {
        guard let privateKey, let publicKey else { throw NoiseError.outOfOrder }
        do {
            return try privateKey.sharedSecretFromKeyAgreement(with: publicKey).withUnsafeBytes { Data($0) }
        } catch {
            throw NoiseError.invalidPublicKey
        }
    }

    private static func publicKey(_ data: Data) throws -> PublicKey {
        do {
            return try PublicKey(rawRepresentation: data)
        } catch {
            throw NoiseError.invalidPublicKey
        }
    }
}
