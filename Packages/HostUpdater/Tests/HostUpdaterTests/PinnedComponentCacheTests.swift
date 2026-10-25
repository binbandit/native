import CryptoKit
import Foundation
import HostUpdater
import Testing

@Suite struct PinnedComponentCacheTests {
    private final class Fixture {
        let parent = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        let bytes = Data("hello".utf8)
        let signer = Curve25519.Signing.PrivateKey()
        var root: URL { parent.appending(path: "cache") }
        var pin: PinnedComponent {
            get throws {
                try PinnedComponent(
                    sha256: "2CF24DBA5FB0A30E26E83B2AC5B9E29E1B161E5C1FA7425E73043362938B9824", byteCount: 5)
            }
        }
        var entry: URL { get throws { root.appending(path: try pin.sha256) } }

        init() throws { try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: false) }
        deinit { try? FileManager.default.removeItem(at: parent) }

        func cache(
            payload: Data? = nil, signature: String? = nil, url: String = "https://example.invalid/release-one/helper",
            fetch: @escaping HostUpdateSource.Fetch = { _ in
                Issue.record("Unexpected network request")
                throw URLError(.notConnectedToInternet)
            }
        ) throws -> PinnedComponentCache {
            try PinnedComponentCache(
                root: root, component: pin,
                signature: signature ?? signer.signature(for: payload ?? bytes).base64EncodedString(),
                key: UpdateSigningKey(base64: signer.publicKey.rawRepresentation.base64EncodedString()),
                artifactURL: #require(URL(string: url)), fetch: fetch)
        }

        func stage(_ data: Data, name: String? = nil) throws {
            try FileManager.default.createDirectory(
                at: root, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
            try data.write(to: root.appending(path: name ?? pin.sha256))
        }
    }

    @Test func constructionDisabledAndOfflineMissDoNotCreateOrFetch() async throws {
        let fixture = try Fixture()
        let cache = try fixture.cache()
        #expect(!FileManager.default.fileExists(atPath: fixture.root.path))
        #expect(try await cache.deliver(scriptingEnabled: false, downloadsAllowed: true) == nil)
        #expect(try await cache.deliver(scriptingEnabled: true) == nil)
        #expect(!FileManager.default.fileExists(atPath: fixture.root.path))
        // An invalid root would fail if a disabled request even tried to inspect the filesystem.
        try fixture.bytes.write(to: fixture.root)
        #expect(try await cache.deliver(scriptingEnabled: false) == nil)
    }

    @Test func offlineHitReverifiesSignature() async throws {
        let fixture = try Fixture()
        try fixture.stage(fixture.bytes)
        #expect(try await fixture.cache().deliver(scriptingEnabled: true) == fixture.bytes)
        let invalid = try fixture.cache(signature: "invalid")
        await #expect(throws: PinnedComponent.VerificationError.invalidSignature) {
            try await invalid.deliver(scriptingEnabled: true)
        }
    }

    @Test func firstDownloadIsPrivateAndReusedAcrossReleaseURLs() async throws {
        let fixture = try Fixture()
        let bytes = fixture.bytes
        let cache = try fixture.cache { url in
            #expect(url.path == "/release-one/helper")
            return bytes
        }
        #expect(try await cache.deliver(scriptingEnabled: true, downloadsAllowed: true) == bytes)
        #expect(try Data(contentsOf: fixture.entry) == bytes)
        let attributes = try FileManager.default.attributesOfItem(atPath: fixture.entry.path)
        #expect((attributes[.posixPermissions] as? NSNumber)?.intValue == 0o600)
        let otherRelease = try fixture.cache(url: "https://mirror.invalid/release-two/renamed")
        #expect(try await otherRelease.deliver(scriptingEnabled: true, downloadsAllowed: true) == bytes)
        #expect(try FileManager.default.contentsOfDirectory(atPath: fixture.root.path) == [fixture.pin.sha256])
    }

    @Test(arguments: [Data("jello".utf8), Data("hello!".utf8)])
    func corruptEntriesFailWithoutRefetchOrReplacement(bytes: Data) async throws {
        let fixture = try Fixture()
        try fixture.stage(bytes)
        let cache = try fixture.cache()
        await #expect(throws: PinnedComponent.VerificationError.self) {
            try await cache.deliver(scriptingEnabled: true, downloadsAllowed: true)
        }
        #expect(try Data(contentsOf: fixture.entry) == bytes)
    }

    @Test(arguments: [false, true])
    func rejectsEntryAndRootSymlinks(rootLink: Bool) async throws {
        let fixture = try Fixture()
        let target = fixture.parent.appending(path: "target")
        if rootLink {
            try FileManager.default.createDirectory(
                at: target, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
            try FileManager.default.createSymbolicLink(at: fixture.root, withDestinationURL: target)
        } else {
            try fixture.stage(fixture.bytes, name: "target")
            try FileManager.default.createSymbolicLink(
                at: fixture.entry, withDestinationURL: fixture.root.appending(path: "target"))
        }
        let cache = try fixture.cache()
        await #expect(throws: PinnedComponentCache.CacheError.unsafeCache) {
            try await cache.deliver(scriptingEnabled: true, downloadsAllowed: true)
        }
    }

    @Test(arguments: ["pin", "signature", "size", "fetch", "cancel"])
    func rejectedDownloadsPreserveOtherHashes(failure: String) async throws {
        let fixture = try Fixture()
        let other = Data("jello".utf8)
        let otherHash = SHA256.hash(data: other).map { String(format: "%02x", $0) }.joined()
        try fixture.stage(other, name: otherHash)
        let bytes = failure == "pin" ? other : (failure == "size" ? Data() : fixture.bytes)
        let cache = try fixture.cache(payload: bytes, signature: failure == "signature" ? "invalid" : nil) { _ in
            if failure == "fetch" { throw URLError(.badServerResponse) }
            if failure == "cancel" { withUnsafeCurrentTask { $0?.cancel() } }
            return bytes
        }
        let task = Task { try await cache.deliver(scriptingEnabled: true, downloadsAllowed: true) }
        switch failure {
        case "pin":
            await #expect(throws: PinnedComponent.VerificationError.checksumMismatch) { try await task.value }
        case "signature":
            await #expect(throws: PinnedComponent.VerificationError.invalidSignature) { try await task.value }
        case "size":
            await #expect(throws: PinnedComponent.VerificationError.sizeMismatch(expected: 5, actual: 0)) {
                try await task.value
            }
        case "cancel":
            await #expect(throws: CancellationError.self) { try await task.value }
        default:
            await #expect(throws: PinnedComponentCache.CacheError.fetchFailed) { try await task.value }
        }
        #expect(try FileManager.default.contentsOfDirectory(atPath: fixture.root.path) == [otherHash])
        #expect(try Data(contentsOf: fixture.root.appending(path: otherHash)) == other)
    }

    @Test func rejectsHTTPBeforeIO() async throws {
        let fixture = try Fixture()
        let cache = try fixture.cache(url: "http://example.invalid/component")
        await #expect(throws: PinnedComponentCache.CacheError.invalidRequest) {
            try await cache.deliver(scriptingEnabled: true, downloadsAllowed: true)
        }
        #expect(!FileManager.default.fileExists(atPath: fixture.root.path))
    }

    @Test func defaultTransportRejectsHTTPFailuresAndOversizedBodies() async throws {
        #expect(URLProtocol.registerClass(ResponseProtocol.self))
        defer { URLProtocol.unregisterClass(ResponseProtocol.self) }
        for response in ["ok", "status", "oversized"] {
            let fixture = try Fixture()
            let cache = try PinnedComponentCache(
                root: fixture.root, component: fixture.pin,
                signature: fixture.signer.signature(for: fixture.bytes).base64EncodedString(),
                key: UpdateSigningKey(base64: fixture.signer.publicKey.rawRepresentation.base64EncodedString()),
                artifactURL: #require(URL(string: "https://component-cache-test.invalid/\(response)")))
            if response == "ok" {
                #expect(try await cache.deliver(scriptingEnabled: true, downloadsAllowed: true) == fixture.bytes)
            } else {
                await #expect(throws: PinnedComponentCache.CacheError.fetchFailed) {
                    try await cache.deliver(scriptingEnabled: true, downloadsAllowed: true)
                }
                #expect(!FileManager.default.fileExists(atPath: fixture.root.path))
            }
        }
    }

    private final class ResponseProtocol: URLProtocol, @unchecked Sendable {
        override class func canInit(with request: URLRequest) -> Bool {
            request.url?.host == "component-cache-test.invalid"
        }
        override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
        override func startLoading() {
            guard let url = request.url,
                let response = HTTPURLResponse(
                    url: url, statusCode: url.path == "/status" ? 503 : 200, httpVersion: nil, headerFields: nil)
            else { return }
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: Data((url.path == "/oversized" ? "hello!" : "hello").utf8))
            client?.urlProtocolDidFinishLoading(self)
        }
        override func stopLoading() {}
    }
}
