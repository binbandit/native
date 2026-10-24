import AppAppearance
import Foundation
import Synchronization

/// A private transport per test, so package tests never contact a release server.
final class CelebrationDownloadFixture: Sendable {
    static let registry = Mutex<[String: CelebrationDownloadFixture]>([:])
    let host = UUID().uuidString.lowercased() + ".example.invalid"
    let cache = CelebrationAssetCache(root: FileManager.default.temporaryDirectory.appending(path: UUID().uuidString))
    let failure: URLError.Code?
    let heldPath: String?
    private let data: Mutex<[String: Data]>
    private let paths = Mutex<[String]>([])
    private let transport = Mutex<URLSession?>(nil)

    var requests: [String] { paths.withLock { $0 } }
    var session: URLSession? {
        get { transport.withLock { $0 } }
        set { transport.withLock { $0 = newValue } }
    }

    init(replies: [String: Data], failure: URLError.Code? = nil, heldPath: String? = nil) {
        data = Mutex(replies)
        self.failure = failure
        self.heldPath = heldPath
        Self.registry.withLock { $0[host] = self }
    }

    func setReplies(_ replies: [String: Data]) { data.withLock { $0 = replies } }

    func reply(to path: String) -> Data? {
        paths.withLock { $0.append(path) }
        return data.withLock { $0[path] }
    }

    func cleanup() {
        session?.invalidateAndCancel()
        Self.registry.withLock { $0[host] = nil }
        try? FileManager.default.removeItem(at: cache.root)
    }
}

final class CelebrationDownloadURLProtocol: URLProtocol, @unchecked Sendable {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let url = request.url, let host = url.host,
            let fixture = CelebrationDownloadFixture.registry.withLock({ $0[host] })
        else { client?.urlProtocol(self, didFailWithError: URLError(.badURL)); return }
        let data = fixture.reply(to: url.path)
        if let failure = fixture.failure {
            client?.urlProtocol(self, didFailWithError: URLError(failure))
            return
        }
        if url.path == fixture.heldPath { return }
        guard
            let response = HTTPURLResponse(
                url: url, statusCode: data == nil ? 404 : 200, httpVersion: nil, headerFields: nil)
        else { return }
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data ?? Data())
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
