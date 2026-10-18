import CryptoKit
import Foundation

/// A long-lived Curve25519 key pair: the host has one, and so does every device. Pairing pins the
/// other side's public key, and every later connection proves possession of the private key in the
/// Noise handshake.
public struct LinkIdentity: Sendable {
    let privateKey: Curve25519.KeyAgreement.PrivateKey

    public init() {
        privateKey = Curve25519.KeyAgreement.PrivateKey()
    }

    public init(rawRepresentation: Data) throws {
        privateKey = try Curve25519.KeyAgreement.PrivateKey(rawRepresentation: rawRepresentation)
    }

    /// The private key's bytes, for its store and nothing else.
    public var rawRepresentation: Data { privateKey.rawRepresentation }

    public var publicKey: LinkPublicKey { LinkPublicKey(privateKey.publicKey) }
}

/// The public half of a `LinkIdentity`, as it's pinned and shown.
public struct LinkPublicKey: Hashable, Sendable, Codable, CustomStringConvertible {
    public let rawRepresentation: Data

    public init(rawRepresentation: Data) throws {
        // Validates the length; Curve25519 accepts any 32 bytes.
        _ = try Curve25519.KeyAgreement.PublicKey(rawRepresentation: rawRepresentation)
        self.rawRepresentation = rawRepresentation
    }

    init(_ key: Curve25519.KeyAgreement.PublicKey) {
        rawRepresentation = key.rawRepresentation
    }

    public init(from decoder: any Decoder) throws {
        let text = try decoder.singleValueContainer().decode(String.self)
        guard let data = Data(base64URLEncoded: text) else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Not base64url"))
        }
        try self.init(rawRepresentation: data)
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawRepresentation.base64URLEncodedString())
    }

    /// A short, stable name for the key: the Bonjour record carries it so a device can tell which
    /// paired host a service is, and people can compare it by eye. 16 characters of base32 (80 bits).
    public var fingerprint: String {
        String(Base32.encode(Data(SHA256.hash(data: rawRepresentation))).prefix(16))
    }

    public var description: String { fingerprint }
}

extension Data {
    init?(base64URLEncoded text: String) {
        var base64 = text.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        base64 += String(repeating: "=", count: (4 - base64.count % 4) % 4)
        self.init(base64Encoded: base64)
    }

    func base64URLEncodedString() -> String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}

/// Crockford's base32 alphabet: no I, L, O or U, so codes read aloud and typed by hand survive.
enum Base32 {
    static let alphabet = Array("0123456789ABCDEFGHJKMNPQRSTVWXYZ")

    static func encode(_ data: Data) -> String {
        var output = ""
        var buffer = 0
        var bits = 0
        for byte in data {
            buffer = (buffer << 8) | Int(byte)
            bits += 8
            while bits >= 5 {
                output.append(alphabet[(buffer >> (bits - 5)) & 31])
                bits -= 5
            }
        }
        if bits > 0 {
            output.append(alphabet[(buffer << (5 - bits)) & 31])
        }
        return output
    }
}
