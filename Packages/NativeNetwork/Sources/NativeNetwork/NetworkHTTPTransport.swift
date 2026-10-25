import Foundation

/// One HTTP hop. Implementations must not follow redirects or perform fallback requests.
/// DNS and connection setup belong behind this seam, after admission.
public protocol NetworkHTTPTransport: Sendable {
    func send(_ url: URL) async throws -> NetworkHTTPResponse
}

public struct NetworkHTTPResponse: Sendable {
    public let data: Data
    public let status: Int
    public let url: URL
    public let location: String?

    public init(data: Data, status: Int, url: URL, location: String? = nil) {
        self.data = data
        self.status = status
        self.url = url
        self.location = location
    }
}

/// Uses system trust and proxy settings, with no shared cookie/credential/cache persistence.
public final class URLSessionNetworkTransport: NetworkHTTPTransport {
    private let session: URLSession

    public init(configuration: URLSessionConfiguration = .ephemeral) {
        configuration.httpCookieStorage = nil
        configuration.urlCredentialStorage = nil
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        session = URLSession(configuration: configuration, delegate: NoRedirects(), delegateQueue: nil)
    }

    deinit { session.invalidateAndCancel() }

    public func send(_ url: URL) async throws -> NetworkHTTPResponse {
        let (data, response) = try await session.data(from: url)
        guard let response = response as? HTTPURLResponse, let finalURL = response.url else {
            throw URLError(.badServerResponse)
        }
        return NetworkHTTPResponse(
            data: data, status: response.statusCode, url: finalURL,
            location: response.value(forHTTPHeaderField: "Location"))
    }
}

private final class NoRedirects: NSObject, URLSessionTaskDelegate {
    func urlSession(
        _ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest, completionHandler: @escaping @Sendable (URLRequest?) -> Void
    ) {
        completionHandler(nil)
    }
}
