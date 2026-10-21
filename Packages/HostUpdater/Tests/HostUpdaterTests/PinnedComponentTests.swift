import CryptoKit
import Foundation
import HostUpdater
import Testing

@Suite struct PinnedComponentTests {
    private static let bytes = Data("hello".utf8)
    private static let compiledSHA256 = "2cf24dba5fb0a30e26e83b2ac5b9e29e1b161e5c1fa7425e73043362938b9824"

    // Each test gets a throwaway key in memory, with no Keychain or filesystem fixtures.
    private let privateKey = Curve25519.Signing.PrivateKey()

    private var key: UpdateSigningKey {
        get throws { try UpdateSigningKey(base64: privateKey.publicKey.rawRepresentation.base64EncodedString()) }
    }

    private var pin: PinnedComponent {
        get throws { try PinnedComponent(sha256: Self.compiledSHA256, byteCount: Self.bytes.count) }
    }

    private func sign(_ data: Data) throws -> String {
        try privateKey.signature(for: data).base64EncodedString()
    }

    @Test(arguments: [false, true])
    func acceptsPinnedSignedBytes(uppercase: Bool) throws {
        let digest = uppercase ? Self.compiledSHA256.uppercased() : Self.compiledSHA256
        let component = try PinnedComponent(sha256: digest, byteCount: Self.bytes.count)
        #expect(component.sha256 == Self.compiledSHA256)
        #expect(component.byteCount == Self.bytes.count)
        try component.verify(Self.bytes, signature: sign(Self.bytes), key: key)
    }

    @Test(arguments: [0, 4, 6])
    func rejectsWrongLength(count: Int) throws {
        let bytes = Data(repeating: 0x61, count: count)
        let component = try pin
        let signature = try sign(bytes)
        let key = try key
        #expect(throws: PinnedComponent.VerificationError.sizeMismatch(expected: Self.bytes.count, actual: count)) {
            try component.verify(bytes, signature: signature, key: key)
        }
    }

    @Test func rejectsAlteredBytes() throws {
        let component = try pin
        let signature = try sign(Self.bytes)
        let key = try key
        #expect(throws: PinnedComponent.VerificationError.checksumMismatch) {
            try component.verify(Data("jello".utf8), signature: signature, key: key)
        }
    }

    @Test func trustedSignatureAndDownloadChecksumCannotReplaceCompiledPin() throws {
        let replacement = Data("jello".utf8)
        let downloadedChecksum = SHA256.hash(data: replacement).map { String(format: "%02x", $0) }.joined()
        let downloadedPin = try PinnedComponent(sha256: downloadedChecksum, byteCount: replacement.count)
        let signature = try sign(replacement)
        let key = try key
        let compiledPin = try pin

        #expect(downloadedPin.sha256 != compiledPin.sha256)
        #expect(key.isValidSignature(signature, for: replacement))
        try downloadedPin.verify(replacement, signature: signature, key: key)
        #expect(throws: PinnedComponent.VerificationError.checksumMismatch) {
            try compiledPin.verify(replacement, signature: signature, key: key)
        }
    }

    @Test func rejectsSignatureFromAnotherKey() throws {
        let otherKey = Curve25519.Signing.PrivateKey()
        let signature = try otherKey.signature(for: Self.bytes).base64EncodedString()
        let component = try pin
        let key = try key
        #expect(throws: PinnedComponent.VerificationError.invalidSignature) {
            try component.verify(Self.bytes, signature: signature, key: key)
        }
    }

    @Test func rejectsTrustedSignatureForOtherBytes() throws {
        let signature = try sign(Data("jello".utf8))
        let component = try pin
        let key = try key
        #expect(throws: PinnedComponent.VerificationError.invalidSignature) {
            try component.verify(Self.bytes, signature: signature, key: key)
        }
    }

    @Test(arguments: [
        "", "not base64!", Data(repeating: 0, count: 63).base64EncodedString(),
        Data(repeating: 0, count: 64).base64EncodedString(), Data(repeating: 0, count: 65).base64EncodedString(),
    ])
    func rejectsMalformedOrInvalidSignatures(signature: String) throws {
        let component = try pin
        let key = try key
        #expect(throws: PinnedComponent.VerificationError.invalidSignature) {
            try component.verify(Self.bytes, signature: signature, key: key)
        }
    }

    @Test(arguments: [
        "", String(repeating: "a", count: 63), String(repeating: "a", count: 65),
        String(repeating: "g", count: 64), String(repeating: "ｆ", count: 64),
        " " + compiledSHA256, compiledSHA256 + "\n", "0x" + compiledSHA256,
    ])
    func rejectsMalformedPins(digest: String) {
        #expect(throws: PinnedComponent.VerificationError.invalidSHA256) {
            try PinnedComponent(sha256: digest, byteCount: Self.bytes.count)
        }
    }

    @Test(arguments: [Int.min, -1, 0])
    func rejectsInvalidByteCounts(count: Int) {
        #expect(throws: PinnedComponent.VerificationError.invalidByteCount) {
            try PinnedComponent(sha256: Self.compiledSHA256, byteCount: count)
        }
    }
}
