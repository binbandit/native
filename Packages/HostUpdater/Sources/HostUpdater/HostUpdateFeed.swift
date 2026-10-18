import Foundation

/// The host feed: what the newest `native-host` on a channel is, and where each platform's binary
/// lives. `scripts/release/release.sh` publishes it as `host-feed.json` beside the appcast, with a
/// detached Ed25519 signature in `host-feed.json.sig` made with the same key as the appcast.
public struct HostUpdateFeed: Codable, Hashable, Sendable {
    public struct Asset: Codable, Hashable, Sendable {
        public var platform: HostPlatform
        public var arch: HostArch
        public var url: URL
        public var size: Int
        /// Hex SHA-256 of the binary.
        public var sha256: String
        /// Base64 Ed25519 signature of the binary.
        public var edSignature: String

        public init(platform: HostPlatform, arch: HostArch, url: URL, size: Int, sha256: String, edSignature: String) {
            self.platform = platform
            self.arch = arch
            self.url = url
            self.size = size
            self.sha256 = sha256
            self.edSignature = edSignature
        }
    }

    /// Bumped on an incompatible change; a host ignores a feed with a schema it doesn't know.
    public static let schema = 1

    public var schema: Int
    public var channel: String
    /// "1.4.0", or "1.5.0-nightly.20261018.abc1234".
    public var version: String
    /// The build number hosts compare, the same `CFBundleVersion` the app has.
    public var build: String
    public var date: Date?
    /// Markdown, drafted from conventional commits.
    public var notes: String?
    public var releaseNotesURL: URL?
    public var assets: [Asset]

    public init(
        channel: String, version: String, build: String, date: Date? = nil, notes: String? = nil,
        releaseNotesURL: URL? = nil, assets: [Asset]
    ) {
        schema = Self.schema
        self.channel = channel
        self.version = version
        self.build = build
        self.date = date
        self.notes = notes
        self.releaseNotesURL = releaseNotesURL
        self.assets = assets
    }

    /// The binary for a machine: its exact architecture first, then a universal macOS build.
    public func asset(for platform: HostPlatform, arch: HostArch) -> Asset? {
        assets.first { $0.platform == platform && $0.arch == arch }
            ?? assets.first { $0.platform == platform && $0.arch == .universal }
    }

    /// Whether the feed's build is newer than `build`. Build numbers only grow (the commit count
    /// on `main`), so this is a numeric comparison.
    public func isNewer(than build: String) -> Bool {
        guard let feed = Int(self.build), let current = Int(build) else { return false }
        return feed > current
    }

    public static func decode(_ data: Data) throws -> HostUpdateFeed {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let feed = try decoder.decode(HostUpdateFeed.self, from: data)
        guard feed.schema == Self.schema else { throw HostUpdateError.unsupportedFeed(schema: feed.schema) }
        return feed
    }

    /// Decodes a feed only once its detached signature checks out.
    public static func verified(_ data: Data, signature: String, key: UpdateSigningKey) throws -> HostUpdateFeed {
        guard key.isValidSignature(signature, for: data) else { throw HostUpdateError.badSignature("the host feed") }
        return try decode(data)
    }
}

public enum HostPlatform: String, Codable, Hashable, Sendable {
    case macos
    case linux
    case unknown

    public init(from decoder: any Decoder) throws {
        self = Self(rawValue: try decoder.singleValueContainer().decode(String.self)) ?? .unknown
    }

    public static var current: HostPlatform {
        #if os(macOS)
        .macos
        #elseif os(Linux)
        .linux
        #else
        .unknown
        #endif
    }
}

public enum HostArch: String, Codable, Hashable, Sendable {
    case universal
    case arm64
    case x64 = "x86_64"
    case unknown

    public init(from decoder: any Decoder) throws {
        self = Self(rawValue: try decoder.singleValueContainer().decode(String.self)) ?? .unknown
    }

    public static var current: HostArch {
        #if arch(arm64)
        .arm64
        #elseif arch(x86_64)
        .x64
        #else
        .unknown
        #endif
    }
}
