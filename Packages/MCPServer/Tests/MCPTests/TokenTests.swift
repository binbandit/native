import Foundation
import Testing

@testable import MCP

struct TokenTests {
    let secret = Data(repeating: 7, count: MCPTokenSigner.secretSize)
    let client = UUID()

    @Test func theSameSecretAndClientAlwaysGiveTheSameToken() {
        let token = MCPTokenSigner(secret: secret, scope: "nightly").token(for: client)
        #expect(MCPTokenSigner(secret: secret, scope: "nightly").token(for: client) == token)
        #expect(MCPTokenSigner(secret: secret, scope: "nightly").client(in: token) == client)
        // Safe as one path segment of the URL.
        #expect(token.allSatisfy { $0.isHexDigit || $0 == "-" || $0 == "." })
    }

    @Test func anotherSecretOrChannelNeverDoes() {
        let token = MCPTokenSigner(secret: secret, scope: "nightly").token(for: client)
        let otherInstall = MCPTokenSigner(secret: MCPTokenSigner.newSecret(), scope: "nightly")
        let otherChannel = MCPTokenSigner(secret: secret, scope: "")
        #expect(otherInstall.token(for: client) != token)
        #expect(otherChannel.token(for: client) != token)
        #expect(otherInstall.client(in: token) == nil)
        #expect(otherChannel.client(in: token) == nil)
    }

    @Test func eachClientGetsItsOwnToken() {
        let signer = MCPTokenSigner(secret: secret, scope: "")
        let other = UUID()
        #expect(signer.token(for: client) != signer.token(for: other))
        // Another client's id with this client's MAC names nobody.
        let mac = signer.token(for: client).split(separator: ".")[1]
        #expect(signer.client(in: "\(other.uuidString.lowercased()).\(mac)") == nil)
    }

    @Test func rejectsAnythingItDidNotIssue() {
        let signer = MCPTokenSigner(secret: secret, scope: "")
        let token = signer.token(for: client)
        let flipped = String(token.dropLast()) + (token.hasSuffix("0") ? "1" : "0")
        for wrong in [flipped, String(token.dropLast(2)), token + "00", token.uppercased(), "", ".", "alice"] {
            #expect(signer.client(in: wrong) == nil, "accepted \(wrong)")
        }
    }

    @Test func newSecretsAreRandom() {
        let secret = MCPTokenSigner.newSecret()
        #expect(secret.count == MCPTokenSigner.secretSize)
        #expect(secret != MCPTokenSigner.newSecret())
    }
}
