import CryptoKit
import Foundation

/// Why a Noise handshake or transport message was refused. Any of these ends the connection: Noise
/// never retries a message.
public enum NoiseError: Error, Equatable, Sendable {
    /// A message failed authentication: wrong keys, a wrong pre-shared key, or tampering.
    case decryptFailed
    /// A message was shorter than its tokens need.
    case truncated
    /// A message was written or read out of turn.
    case outOfOrder
    /// A pre-shared key was missing or not 32 bytes.
    case invalidPreSharedKey
    case invalidPublicKey
    /// 2^64 - 1 messages with one key; the connection has to start over.
    case nonceExhausted
}

/// Noise's CipherState for ChaChaPoly: a key, once one is mixed in, and a counter nonce that never
/// repeats under it. Without a key it passes data through, as the handshake's first message needs.
struct NoiseCipherState: Sendable {
    static let tagLength = 16

    private var key: SymmetricKey?
    private var nonce: UInt64 = 0

    init(key: SymmetricKey? = nil) {
        self.key = key
    }

    var hasKey: Bool { key != nil }

    mutating func encrypt(_ plaintext: Data, associatedData: Data) throws -> Data {
        guard let key else { return plaintext }
        let box = try ChaChaPoly.seal(plaintext, using: key, nonce: try nextNonce(), authenticating: associatedData)
        nonce += 1
        return box.ciphertext + box.tag
    }

    mutating func decrypt(_ ciphertext: Data, associatedData: Data) throws -> Data {
        guard let key else { return ciphertext }
        guard ciphertext.count >= Self.tagLength else { throw NoiseError.truncated }
        let plaintext: Data
        do {
            let box = try ChaChaPoly.SealedBox(
                nonce: try nextNonce(),
                ciphertext: ciphertext.prefix(ciphertext.count - Self.tagLength),
                tag: ciphertext.suffix(Self.tagLength)
            )
            plaintext = try ChaChaPoly.open(box, using: key, authenticating: associatedData)
        } catch {
            throw NoiseError.decryptFailed
        }
        nonce += 1
        return plaintext
    }

    /// 32 bits of zeros, then the counter in little-endian, as the Noise spec lays out ChaChaPoly's nonce.
    private func nextNonce() throws -> ChaChaPoly.Nonce {
        // The spec reserves the maximum value.
        guard nonce < .max else { throw NoiseError.nonceExhausted }
        var bytes = Data(count: 4)
        withUnsafeBytes(of: nonce.littleEndian) { bytes.append(contentsOf: $0) }
        return try ChaChaPoly.Nonce(data: bytes)
    }
}
