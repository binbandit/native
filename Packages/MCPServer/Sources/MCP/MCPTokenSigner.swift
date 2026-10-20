import CryptoKit
import Foundation

/// Signs and checks the tokens in an MCP server's URLs (`/mcp/<token>`).
///
/// A token is a client's id and an HMAC-SHA256 of it under a secret only the server holds:
/// `<uuid>.<64 hex digits>`. The server can tell who's calling from the token alone, with no table
/// that has to survive a relaunch, and the same client gets the same token for as long as the
/// secret lasts. The client id isn't a secret; the MAC is the credential.
///
/// The scope (Native's host channel) is signed too, so a token never works for another channel's
/// server, even one that somehow had the same secret.
public struct MCPTokenSigner: Sendable {
    /// A secret's size in bytes.
    public static let secretSize = 32

    private let key: SymmetricKey
    private let scope: String

    public init(secret: some ContiguousBytes, scope: String) {
        key = SymmetricKey(data: secret)
        self.scope = scope
    }

    /// A new secret from the system's CSPRNG.
    public static func newSecret() -> Data {
        SymmetricKey(size: .bits256).withUnsafeBytes { Data($0) }
    }

    public func token(for client: UUID) -> String {
        let code = HMAC<SHA256>.authenticationCode(for: message(client), using: key)
        return client.uuidString.lowercased() + "." + code.map { String(format: "%02x", $0) }.joined()
    }

    /// The client a token names, or nil unless this signer issued it. The MAC is compared in
    /// constant time, so how long a wrong token takes says nothing about how close it was.
    public func client(in token: some StringProtocol) -> UUID? {
        guard let dot = token.lastIndex(of: "."), let client = UUID(uuidString: String(token[..<dot])),
            let code = Self.bytes(hex: token[token.index(after: dot)...]), code.count == SHA256.byteCount,
            HMAC<SHA256>.isValidAuthenticationCode(code, authenticating: message(client), using: key)
        else { return nil }
        return client
    }

    /// Versioned, so a later token format can never be mistaken for this one.
    private func message(_ client: UUID) -> Data {
        Data("native-mcp-token/1\n\(scope)\n\(client.uuidString.lowercased())".utf8)
    }

    private static func bytes(hex: some StringProtocol) -> Data? {
        let digits = Array(hex.utf8)
        guard digits.count.isMultiple(of: 2) else { return nil }
        var bytes = Data(capacity: digits.count / 2)
        for index in stride(from: 0, to: digits.count, by: 2) {
            guard let high = nibble(digits[index]), let low = nibble(digits[index + 1]) else { return nil }
            bytes.append(high << 4 | low)
        }
        return bytes
    }

    private static func nibble(_ digit: UInt8) -> UInt8? {
        switch digit {
        case UInt8(ascii: "0")...UInt8(ascii: "9"): digit - UInt8(ascii: "0")
        case UInt8(ascii: "a")...UInt8(ascii: "f"): digit - UInt8(ascii: "a") + 10
        default: nil
        }
    }
}
