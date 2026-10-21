import CryptoKit
import Foundation
import PluginCatalog
import Testing

struct PluginCatalogIndexTests {
    private let key = Curve25519.Signing.PrivateKey()
    private var entry: [String: Any] {
        [
            "id": "example", "version": "1.0.0", "repository": "https://example.org/owner/plugins",
            "commit": String(repeating: "a", count: 40), "path": "plugins/example",
            "archiveURL": "https://example.org/assets/example.tar", "sha256": String(repeating: "b", count: 64),
            "size": 123,
        ]
    }
    private func data(_ entries: [[String: Any]], schema: Int = 1) throws -> Data {
        try JSONSerialization.data(withJSONObject: ["schema": schema, "plugins": entries, "future": true])
    }
    private func verify(_ data: Data) throws -> PluginCatalogIndex {
        try PluginCatalogIndex.verified(
            data, signature: key.signature(for: data).base64EncodedString(), publicKey: key.publicKey.rawRepresentation)
    }

    @Test func validIndexesAndUnknownFields() throws {
        var second = entry
        second["id"] = "other-2"
        second["version"] = "Preview build 7"
        second["future"] = ["ignored": "\0"]
        let index = try verify(data([entry, second]))
        #expect(index.schema == 1)
        #expect(index.plugins.map(\.id) == ["example", "other-2"])
        #expect(index.plugins[1].version == "Preview build 7")
        #expect(index.plugins[0].repository.absoluteString == "https://example.org/owner/plugins")
        #expect(index.plugins[0].size == 123)
        #expect(try verify(data([])).plugins.isEmpty)
    }

    @Test func signatureRejectionPrecedesDecoding() throws {
        let original = try data([entry])
        let signature = try key.signature(for: original).base64EncodedString()
        for changed in [original + Data(" ".utf8), Data("not JSON".utf8), original + Data([0])] {
            #expect(throws: PluginCatalogError.signatureMismatch) {
                try PluginCatalogIndex.verified(
                    changed, signature: signature, publicKey: key.publicKey.rawRepresentation)
            }
        }
        #expect(throws: PluginCatalogError.signatureMismatch) {
            try PluginCatalogIndex.verified(
                original, signature: signature, publicKey: Curve25519.Signing.PrivateKey().publicKey.rawRepresentation)
        }
        for signature in ["", "not base64!", Data(repeating: 0, count: 63).base64EncodedString()] {
            #expect(throws: PluginCatalogError.malformedSignature) {
                try PluginCatalogIndex.verified(
                    Data("{".utf8), signature: signature, publicKey: key.publicKey.rawRepresentation)
            }
        }
        #expect(throws: PluginCatalogError.malformedPublicKey) {
            try PluginCatalogIndex.verified(original, signature: signature, publicKey: Data(repeating: 0, count: 31))
        }
    }

    @Test func signedInvalidDocuments() throws {
        #expect(throws: PluginCatalogError.unsupportedSchema(2)) { try verify(data([], schema: 2)) }
        #expect(throws: PluginCatalogError.duplicateID("example")) { try verify(data([entry, entry])) }
        for malformed in [Data("{".utf8), Data(#"{"schema":1}"#.utf8), Data(#"{"schema":1,"plugins":null}"#.utf8)] {
            #expect(throws: PluginCatalogError.malformedJSON) { try verify(malformed) }
        }
        var missing = entry
        missing.removeValue(forKey: "version")
        #expect(throws: PluginCatalogError.malformedJSON) { try verify(data([missing])) }
        let json = try #require(String(data: data([]), encoding: .utf8))
        for encoding: String.Encoding in [
            .utf16, .utf16LittleEndian, .utf16BigEndian, .utf32LittleEndian, .utf32BigEndian,
        ] {
            let alternate = try #require(json.data(using: encoding))
            #expect(throws: PluginCatalogError.malformedJSON) { try verify(alternate) }
        }
    }

    @Test func signedMalformedEntries() throws {
        let cases: [(PluginCatalogEntry.Field, [Any])] = [
            (.id, ["", "Upper", "-a", "a-", "a--b", "a_b", "a\n", "é"]),
            (.version, [""]),
            (.repository, ["http://example.org", "/relative", "https:///", "https://user@example.org"]),
            (.archiveURL, ["file:///tmp/a", "https://user:pass@example.org/a", "https://example.org/a b"]),
            (.commit, [String(repeating: "a", count: 39), String(repeating: "A", count: 40), "main"]),
            (.sha256, [String(repeating: "b", count: 63), String(repeating: "B", count: 64), "xyz"]),
            (.path, ["", "/a", "a/", "a//b", ".", "..", "a/./b", "a/../b", "a\\b", "a\0b"]),
            (.size, [0, -1]),
        ]
        for (field, values) in cases {
            for value in values {
                var invalid = entry
                invalid[field.rawValue] = value
                let id = invalid["id"] as? String ?? ""
                #expect(throws: PluginCatalogError.invalidEntry(id: id, field: field)) { try verify(data([invalid])) }
            }
        }
        for value: Any in ["123", 1.5, NSNull()] {
            var invalid = entry
            invalid["size"] = value
            #expect(throws: PluginCatalogError.malformedJSON) { try verify(data([invalid])) }
        }
    }
}
