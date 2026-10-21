import Foundation

/// A trusted content identity, intended to be compiled into the app independently of downloads.
/// A signed downloadable descriptor must never supply or replace this pin.
public struct PinnedComponent: Sendable {
    public enum VerificationError: Error, Equatable, Sendable {
        case invalidSHA256
        case invalidByteCount
        case sizeMismatch(expected: Int, actual: Int)
        case checksumMismatch
        case invalidSignature
    }

    public let sha256: String
    public let byteCount: Int

    /// Requires exactly 64 ASCII hexadecimal digits and a positive byte count.
    /// Uppercase hexadecimal is accepted and stored in lowercase; whitespace is rejected.
    public init(sha256: String, byteCount: Int) throws(VerificationError) {
        guard sha256.utf8.count == 64,
            sha256.utf8.allSatisfy({
                (48...57).contains($0) || (65...70).contains($0) || (97...102).contains($0)
            })
        else { throw .invalidSHA256 }
        guard byteCount > 0 else { throw .invalidByteCount }
        self.sha256 = sha256.lowercased()
        self.byteCount = byteCount
    }

    /// Checks the exact size, independent content pin, then detached base64 Ed25519 signature.
    /// This only verifies supplied bytes, without I/O or permission to execute them.
    public func verify(_ data: Data, signature: String, key: UpdateSigningKey) throws(VerificationError) {
        guard data.count == byteCount else { throw .sizeMismatch(expected: byteCount, actual: data.count) }
        guard UpdateSigningKey.sha256(data) == sha256 else { throw .checksumMismatch }
        guard key.isValidSignature(signature, for: data) else { throw .invalidSignature }
    }
}
