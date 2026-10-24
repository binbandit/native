import CryptoKit
import Foundation
import NativePolicy
import PluginCatalog
import Testing

struct PluginCatalogSourceTests {
    private let key = Curve25519.Signing.PrivateKey()
    private let bytes = Data("{\r\n  \"plugins\" : [], \"schema\" : 1\r\n}\n".utf8)

    private func url(_ value: String = "https://catalog.example/index%20v1.json?channel=stable") throws -> URL {
        try #require(URL(string: value))
    }

    private func source(_ transport: Transport) throws -> PluginCatalogSource {
        PluginCatalogSource(defaultIndexURL: try url(), publicKey: key.publicKey.rawRepresentation) {
            try await transport.fetch($0)
        }
    }

    private func transport() throws -> Transport {
        Transport(bytes: bytes, signature: Data(try key.signature(for: bytes).base64EncodedString().utf8))
    }

    @Test func constructionAndDisabledPolicyMakeNoCalls() async throws {
        let transport = try transport()
        let source = try source(transport)
        #expect(await transport.calls.isEmpty)
        var policy = NativePolicy().catalog
        policy.isEnabled = false
        policy.indexURL = try url("http://user:password@mirror.example/index.json")
        await #expect(throws: PluginCatalogSource.LoadError.disabled) { try await source.load(policy: policy) }
        #expect(await transport.calls.isEmpty)
    }

    @Test(arguments: [false, true]) func explicitLoadPreservesSignedBytes(mirror: Bool) async throws {
        let transport = try transport()
        let source = try source(transport)
        var policy = NativePolicy().catalog
        if mirror { policy.indexURL = try url("https://mirror.example/internal/index.json?version=1") }
        let index = try await source.load(policy: policy)
        #expect(index.schema == 1 && index.plugins.isEmpty)
        let expected = try url(
            mirror
                ? "https://mirror.example/internal/index.json?version=1"
                : "https://catalog.example/index%20v1.json?channel=stable")
        let signature = try url(
            mirror
                ? "https://mirror.example/internal/index.json.sig?version=1"
                : "https://catalog.example/index%20v1.json.sig?channel=stable")
        #expect(await transport.calls == [expected, signature])
    }

    @Test func badSignatureNeverReturnsAnIndex() async throws {
        let transport = Transport(
            bytes: bytes + Data(" ".utf8), signature: try key.signature(for: bytes).base64EncodedData())
        await #expect(throws: PluginCatalogError.signatureMismatch) {
            try await source(transport).load(policy: NativePolicy().catalog)
        }
    }

    @Test(arguments: [1, 2]) func mirrorFailureNeverFallsBack(failingCall: Int) async throws {
        let transport = try transport()
        await transport.fail(on: failingCall)
        var policy = NativePolicy().catalog
        policy.indexURL = try url("https://mirror.example/index.json")
        await #expect(throws: URLError(.notConnectedToInternet)) { try await source(transport).load(policy: policy) }
        let calls = await transport.calls
        #expect(calls.count == failingCall)
        #expect(calls.allSatisfy { $0.host == "mirror.example" })
    }

    @Test(arguments: [
        "http://catalog.example/index", "https://user:pass@catalog.example/index", "/index",
        "https://catalog.example/index#fragment",
    ])
    func invalidEndpointsMakeNoCalls(endpoint: String) async throws {
        let transport = try transport()
        let invalid = try url(endpoint)
        let source = PluginCatalogSource(defaultIndexURL: invalid, publicKey: key.publicKey.rawRepresentation) {
            try await transport.fetch($0)
        }
        var policy = NativePolicy().catalog
        await #expect(throws: PluginCatalogSource.LoadError.invalidEndpoint) { try await source.load(policy: policy) }
        policy.indexURL = invalid
        await #expect(throws: PluginCatalogSource.LoadError.invalidEndpoint) {
            try await self.source(transport).load(policy: policy)
        }
        #expect(await transport.calls.isEmpty)
    }

    @Test func cancelledTaskMakesNoCalls() async throws {
        let transport = try transport()
        let source = try source(transport)
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await source.load(policy: NativePolicy().catalog)
        }
        await #expect(throws: CancellationError.self) { try await task.value }
        #expect(await transport.calls.isEmpty)
    }

    @Test(arguments: [1, 2]) func cancellationDuringFetch(stoppingCall: Int) async throws {
        let transport = try transport()
        let (started, signal) = AsyncStream<Void>.makeStream()
        let source = PluginCatalogSource(defaultIndexURL: try url(), publicKey: key.publicKey.rawRepresentation) {
            let data = try await transport.fetch($0)
            if await transport.calls.count == stoppingCall {
                signal.yield(())
                try await Task.sleep(for: .seconds(30))
            }
            return data
        }
        let task = Task { try await source.load(policy: NativePolicy().catalog) }
        for await _ in started { break }
        task.cancel()
        await #expect(throws: CancellationError.self) { try await task.value }
        #expect(await transport.calls.count == stoppingCall)
        signal.finish()
    }

    @Test(arguments: [200, 299, 301, 404, 503, -999]) func httpStatus(status: Int) async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [HTTPFixture.self]
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        let endpoint = try url("https://fixture.example/\(status)")
        if status == -999 {
            await #expect {
                try await PluginCatalogSource.download(endpoint, session: session)
            } throws: {
                ($0 as? URLError)?.code == .cancelled
            }
        } else if (200..<300).contains(status) {
            #expect(try await PluginCatalogSource.download(endpoint, session: session) == Data("original bytes".utf8))
        } else {
            await #expect(throws: PluginCatalogSource.LoadError.httpStatus(status)) {
                try await PluginCatalogSource.download(endpoint, session: session)
            }
        }
    }

    private actor Transport {
        var calls: [URL] = []
        let bytes: Data
        let signature: Data
        var failingCall: Int?

        init(bytes: Data, signature: Data) {
            self.bytes = bytes
            self.signature = signature
        }

        func fail(on call: Int) { failingCall = call }

        func fetch(_ url: URL) throws -> Data {
            calls.append(url)
            if calls.count == failingCall { throw URLError(.notConnectedToInternet) }
            return url.pathExtension == "sig" ? signature : bytes
        }
    }

    private final class HTTPFixture: URLProtocol, @unchecked Sendable {
        override class func canInit(with request: URLRequest) -> Bool { true }
        override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
        override func startLoading() {
            guard let url = request.url, let status = Int(url.lastPathComponent),
                let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: nil, headerFields: nil)
            else {
                client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
                return
            }
            if status == -999 {
                client?.urlProtocol(self, didFailWithError: URLError(.cancelled))
                return
            }
            if status == 301, let target = URL(string: "http://fixture.example/200") {
                client?.urlProtocol(self, wasRedirectedTo: URLRequest(url: target), redirectResponse: response)
            }
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: Data("original bytes".utf8))
            client?.urlProtocolDidFinishLoading(self)
        }
        override func stopLoading() {}
    }
}
