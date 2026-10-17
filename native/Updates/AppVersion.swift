import Foundation

/// This build's version, channel and update feed, read once from its Info.plist.
struct AppVersion: Equatable, Sendable {
    /// "1.4.0", or "1.5.0-nightly.20261018.abc1234" for Nightly (`CFBundleShortVersionString`).
    let version: String
    /// The build number Sparkle compares (`CFBundleVersion`).
    let build: String
    let channel: ReleaseChannel
    /// `SUFeedURL`, from Config/*.xcconfig.
    let feedURL: URL?
    /// Whether `SUPublicEDKey` is set; Sparkle won't install an update it can't verify.
    let hasSigningKey: Bool
    /// "owner/name" on GitHub, for release-notes links.
    let repository: String?

    static let current = AppVersion(info: Bundle.main.infoDictionary ?? [:])

    init(info: [String: Any], channel: ReleaseChannel = .current) {
        version = info["CFBundleShortVersionString"] as? String ?? "0"
        build = info["CFBundleVersion"] as? String ?? "0"
        self.channel = channel
        feedURL = (info["SUFeedURL"] as? String).flatMap { $0.isEmpty ? nil : URL(string: $0) }
        hasSigningKey = !((info["SUPublicEDKey"] as? String) ?? "").isEmpty
        repository = (info["NativeGitHubRepository"] as? String).flatMap { Self.isPlaceholder($0) ? nil : $0 }
    }

    /// The feed is real (not the xcconfig placeholder) and updates can be verified.
    var isUpdateConfigured: Bool {
        guard let feedURL, hasSigningKey else { return false }
        return !Self.isPlaceholder(feedURL.absoluteString)
    }

    /// "1.4.0 (1234)".
    var displayVersion: String { "\(version) (\(build))" }

    /// The release page for this build: its tag for stable and beta, the rolling release for Nightly.
    var releaseNotesURL: URL? {
        guard let repository else { return nil }
        let tag = channel.isNightly ? "nightly" : "v\(version)"
        return URL(string: "https://github.com/\(repository)/releases/tag/\(tag)")
    }

    /// Every release, newest first.
    var allReleasesURL: URL? {
        repository.flatMap { URL(string: "https://github.com/\($0)/releases") }
    }

    private static func isPlaceholder(_ value: String) -> Bool {
        value.isEmpty || value.contains("PLACEHOLDER")
    }
}
