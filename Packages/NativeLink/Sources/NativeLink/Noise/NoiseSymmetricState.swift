import CryptoKit
import Foundation

/// Noise's SymmetricState with SHA-256: the chaining key, the handshake hash that every message is
/// bound to, and the cipher the handshake encrypts with once keys exist.
struct NoiseSymmetricState: Sendable {
    static let hashLength = 32

    private(set) var cipher = NoiseCipherState()
    private var chainingKey: Data
    private(set) var hash: Data

    init(protocolName: String) {
        let name = Data(protocolName.utf8)
        hash =
            name.count <= Self.hashLength
            ? name + Data(count: Self.hashLength - name.count) : Data(SHA256.hash(data: name))
        chainingKey = hash
    }

    mutating func mixKey(_ inputKeyMaterial: Data) {
        let outputs = derive(from: inputKeyMaterial, count: 2)
        chainingKey = outputs[0]
        cipher = NoiseCipherState(key: SymmetricKey(data: outputs[1]))
    }

    mutating func mixHash(_ data: Data) {
        hash = Data(SHA256.hash(data: hash + data))
    }

    mutating func mixKeyAndHash(_ inputKeyMaterial: Data) {
        let outputs = derive(from: inputKeyMaterial, count: 3)
        chainingKey = outputs[0]
        mixHash(outputs[1])
        cipher = NoiseCipherState(key: SymmetricKey(data: outputs[2]))
    }

    mutating func encryptAndHash(_ plaintext: Data) throws -> Data {
        let ciphertext = try cipher.encrypt(plaintext, associatedData: hash)
        mixHash(ciphertext)
        return ciphertext
    }

    mutating func decryptAndHash(_ ciphertext: Data) throws -> Data {
        let plaintext = try cipher.decrypt(ciphertext, associatedData: hash)
        mixHash(ciphertext)
        return plaintext
    }

    /// The two transport ciphers: the initiator sends with the first, the responder with the second.
    func split() -> (NoiseCipherState, NoiseCipherState) {
        let outputs = derive(from: Data(), count: 2)
        return (
            NoiseCipherState(key: SymmetricKey(data: outputs[0])), NoiseCipherState(key: SymmetricKey(data: outputs[1]))
        )
    }

    /// Noise's HKDF is RFC 5869's with the chaining key as salt and no info, so CryptoKit's computes it.
    private func derive(from inputKeyMaterial: Data, count: Int) -> [Data] {
        let output = HKDF<SHA256>.deriveKey(
            inputKeyMaterial: SymmetricKey(data: inputKeyMaterial),
            salt: chainingKey,
            info: Data(),
            outputByteCount: Self.hashLength * count
        )
        let bytes = output.withUnsafeBytes { Data($0) }
        return (0..<count).map { index in
            bytes.subdata(in: (index * Self.hashLength)..<((index + 1) * Self.hashLength))
        }
    }
}
