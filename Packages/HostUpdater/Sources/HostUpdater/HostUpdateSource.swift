import Foundation

#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Where a standalone host finds its updates: the channel's host feed on GitHub Releases, checked
/// against Native's signing key before anything is believed or installed.
public struct HostUpdateSource: Sendable {
    public typealias Fetch = @Sendable (URL) async throws -> Data

    public let feedURL: URL
    public let key: UpdateSigningKey
    private let fetch: Fetch

    public init(feedURL: URL, key: UpdateSigningKey, fetch: @escaping Fetch = HostUpdateSource.download) {
        self.feedURL = feedURL
        self.key = key
        self.fetch = fetch
    }

    /// The feed for a channel, beside that channel's appcast. Betas are prereleases, so their feed
    /// is published on the latest stable release, like the appcast (docs/releasing.md).
    public static func feedURL(repository: String, channel: String) -> URL? {
        let releases = "https://github.com/\(repository)/releases"
        return switch channel {
        case "nightly": URL(string: "\(releases)/download/nightly/host-feed.json")
        case "beta": URL(string: "\(releases)/latest/download/host-feed-beta.json")
        default: URL(string: "\(releases)/latest/download/host-feed.json")
        }
    }

    /// An organization's internal feed (`policy.updates.feedURL`) points at its appcast; its host
    /// feed sits beside it, so one setting moves the app and its standalone hosts together.
    public static func feedURL(besideAppcast appcast: URL, channel: String) -> URL {
        appcast.deletingLastPathComponent().appending(
            path: channel == "beta" ? "host-feed-beta.json" : "host-feed.json")
    }

    /// The newest release on the channel, once its signature checks out.
    public func latest() async throws -> HostUpdateFeed {
        async let feed = fetch(feedURL)
        async let signature = fetch(feedURL.appendingPathExtension("sig"))
        return try HostUpdateFeed.verified(
            try await feed, signature: String(decoding: try await signature, as: UTF8.self), key: key)
    }

    /// Downloads this machine's binary from `feed` and stages it, verified. Nothing runs it yet.
    public func download(
        _ feed: HostUpdateFeed, into installer: HostBinaryInstaller,
        platform: HostPlatform = .current, arch: HostArch = .current
    ) async throws {
        guard let asset = feed.asset(for: platform, arch: arch) else { throw HostUpdateError.noBinary(platform, arch) }
        try installer.stage(try await fetch(asset.url), asset: asset, build: feed.build)
    }

    /// GitHub's release downloads redirect to a CDN; URLSession follows them.
    public static let download: Fetch = { url in
        let (data, response) = try await URLSession.shared.data(from: url)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw URLError(.badServerResponse, userInfo: [NSURLErrorFailingURLErrorKey: url])
        }
        return data
    }
}
