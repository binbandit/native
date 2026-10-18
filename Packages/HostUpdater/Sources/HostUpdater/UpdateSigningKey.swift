import Foundation

#if canImport(CryptoKit)
import CryptoKit
#else
#error("HostUpdater needs Ed25519: add swift-crypto for this platform (Package.swift, TODO(linux)).")
#endif

/// Sparkle's EdDSA public key (`NATIVE_SPARKLE_PUBLIC_KEY`): one key signs the appcast, the host
/// feed and every binary. Sparkle signs with standard Ed25519, so CryptoKit verifies its signatures.
public struct UpdateSigningKey: Sendable {
    private let key: Curve25519.Signing.PublicKey

    /// - Parameter base64: the public key as `generate_keys` prints it.
    public init(base64: String) throws {
        guard let raw = Data(base64Encoded: base64.trimmingCharacters(in: .whitespacesAndNewlines)),
            let key = try? Curve25519.Signing.PublicKey(rawRepresentation: raw)
        else { throw HostUpdateError.badKey }
        self.key = key
    }

    public func isValidSignature(_ base64: String, for data: Data) -> Bool {
        guard let signature = Data(base64Encoded: base64.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            return false
        }
        return key.isValidSignature(signature, for: data)
    }

    static func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}

public enum HostUpdateError: Error, Equatable, LocalizedError {
    case badKey
    case badSignature(String)
    case checksumMismatch
    case sizeMismatch
    case unsupportedFeed(schema: Int)
    case noBinary(HostPlatform, HostArch)
    case notStaged(build: String)
    case notInstalled

    public var errorDescription: String? {
        switch self {
        case .badKey: "The update signing key isn't a valid Ed25519 public key."
        case .badSignature(let what): "The signature on \(what) doesn't match Native's signing key."
        case .checksumMismatch: "The downloaded host doesn't match the checksum in the feed."
        case .sizeMismatch: "The downloaded host isn't the size the feed says."
        case .unsupportedFeed(let schema): "The host feed uses format \(schema), which this host doesn't understand."
        case .noBinary(let platform, let arch): "This release has no host for \(platform.rawValue) \(arch.rawValue)."
        case .notStaged(let build): "Build \(build) hasn't been downloaded and verified."
        case .notInstalled: "This host wasn't installed by Native's updater, so it can't replace itself."
        }
    }
}
