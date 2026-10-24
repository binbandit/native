import Foundation
import NativePolicy

/// An on-demand catalog reader. Construction performs no fetching and selects no production trust root.
public struct PluginCatalogSource: Sendable {
    public typealias Fetch = @Sendable (URL) async throws -> Data

    public enum LoadError: Error, Equatable, Sendable {
        case disabled
        case invalidEndpoint
        case invalidResponse
        case httpStatus(Int)
    }

    private let defaultIndexURL: URL
    private let publicKey: Data
    private let fetch: Fetch

    public init(
        defaultIndexURL: URL, publicKey: Data,
        fetch: @escaping Fetch = { try await PluginCatalogSource.download($0) }
    ) {
        self.defaultIndexURL = defaultIndexURL
        self.publicKey = publicKey
        self.fetch = fetch
    }

    /// Pass the current effective policy for each load. A mirror is authoritative, including on failure.
    public func load(policy: NativePolicy.Catalog) async throws -> PluginCatalogIndex {
        guard policy.isEnabled else { throw LoadError.disabled }
        try Task.checkCancellation()
        let indexURL = policy.indexURL ?? defaultIndexURL
        let signatureURL = indexURL.appendingPathExtension("sig")
        try Self.validate(indexURL)
        try Self.validate(signatureURL)
        let data = try await fetch(indexURL)
        try Task.checkCancellation()
        let signatureData = try await fetch(signatureURL)
        try Task.checkCancellation()
        guard let signature = String(data: signatureData, encoding: .utf8) else {
            throw PluginCatalogError.malformedSignature
        }
        return try PluginCatalogIndex.verified(data, signature: signature, publicKey: publicKey)
    }

    /// The session can be supplied for offline URLProtocol tests. Redirects are never followed.
    public static func download(_ url: URL, session: URLSession = .shared) async throws -> Data {
        try Task.checkCancellation()
        try validate(url)
        let request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData)
        let (data, response) = try await session.data(for: request, delegate: NoRedirects())
        try Task.checkCancellation()
        guard let response = response as? HTTPURLResponse else { throw LoadError.invalidResponse }
        guard (200..<300).contains(response.statusCode) else { throw LoadError.httpStatus(response.statusCode) }
        return data
    }

    private static func validate(_ url: URL) throws {
        guard let parts = URLComponents(url: url, resolvingAgainstBaseURL: false),
            parts.scheme?.lowercased() == "https", let host = parts.host, !host.isEmpty,
            parts.user == nil, parts.password == nil, parts.fragment == nil
        else { throw LoadError.invalidEndpoint }
    }

    private final class NoRedirects: NSObject, URLSessionTaskDelegate {
        func urlSession(
            _ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
            newRequest request: URLRequest, completionHandler: @escaping @Sendable (URLRequest?) -> Void
        ) {
            // A redirect must not bypass the selected endpoint or its HTTPS requirement.
            completionHandler(nil)
        }
    }
}
