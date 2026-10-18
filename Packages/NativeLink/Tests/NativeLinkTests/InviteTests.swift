import Foundation
import NativeHostProtocol
import Testing

@testable import NativeLink

@Suite struct InviteTests {
    @Test func roundTripsThroughItsLink() throws {
        let invite = PairingInvite(
            hostID: HostID(), hostKey: LinkIdentity().publicKey, secret: Data(repeating: 7, count: 32),
            hostName: "Brayden’s MacBook Pro", expiresAt: Date(timeIntervalSince1970: 1_800_000_300),
            addresses: [
                LinkAddress(kind: .bonjour, host: "Brayden’s MacBook Pro"),
                LinkAddress(kind: .lan, host: "192.168.1.20", port: 47_118),
            ])
        let link = invite.url.absoluteString
        #expect(link.hasPrefix("nativecompanion://pair#"))
        // Small enough for a comfortable QR code.
        #expect(link.count < 512)
        #expect(try PairingInvite(url: "  \(link)\n") == invite)
    }

    @Test func rejectsWhatIsntAnInvite() {
        #expect(throws: PairingInvite.ParseError.notAnInvite) { try PairingInvite(url: "https://example.com") }
        #expect(throws: PairingInvite.ParseError.notAnInvite) { try PairingInvite(url: "nativecompanion://pair#bm9wZQ") }
        let newer = Data(#"{"v":9}"#.utf8).base64URLEncodedString()
        #expect(throws: PairingInvite.ParseError.newerVersion(9)) { try PairingInvite(url: "nativecompanion://pair#\(newer)") }
    }

    @Test func readsTypedCodesForgivingly() throws {
        #expect(PairingCode(typed: "k7q 4mx")?.rawValue == "K7Q4MX")
        #expect(PairingCode(typed: "OIL-234")?.rawValue == "011234")
        #expect(PairingCode(typed: "K7Q4M") == nil)
        #expect(PairingCode(typed: "K7Q4MU") == nil, "U isn't in Crockford's alphabet")
        #expect(try require(PairingCode(typed: "K7Q4MX")).description == "K7Q 4MX")
    }

    @Test func fingerprintsAreStableAndShort() throws {
        let key = LinkIdentity().publicKey
        #expect(key.fingerprint.count == 16)
        #expect(try LinkPublicKey(rawRepresentation: key.rawRepresentation).fingerprint == key.fingerprint)
        #expect(LinkInterfaces.isTailnet("100.101.2.3"))
        #expect(!LinkInterfaces.isTailnet("100.20.2.3"))
    }
}
