import Foundation

/// Avatars have no credentials attached. URLCache keeps a last-known picture available offline;
/// small in-memory entries also avoid decoding/downloading on every sidebar update.
public actor GitHubAvatarCache {
    public static let shared = GitHubAvatarCache()
    private var images: [URL: Data] = [:]
    private let session: URLSession

    public init() {
        let configuration = URLSessionConfiguration.default
        configuration.urlCache = URLCache(memoryCapacity: 4 * 1_024 * 1_024, diskCapacity: 16 * 1_024 * 1_024)
        configuration.timeoutIntervalForRequest = 10
        session = URLSession(configuration: configuration)
    }

    public func image(at url: URL) async -> Data? {
        guard url.scheme == "https" else { return nil }
        if let cached = images[url] { return cached }
        let request = URLRequest(url: url, cachePolicy: .returnCacheDataElseLoad)
        guard let (data, response) = try? await session.data(for: request),
            let response = response as? HTTPURLResponse, response.statusCode == 200,
            response.mimeType?.hasPrefix("image/") == true, data.count <= 2 * 1_024 * 1_024
        else { return nil }
        if images.count >= 50 { images.removeAll() }
        images[url] = data
        return data
    }
}
