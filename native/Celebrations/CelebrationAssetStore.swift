import AppAppearance
import Foundation
import NativePolicy
import Observation

/// Native's celebration icons that download instead of shipping in the app: fetched from the latest
/// release when someone chooses a celebration (or a week before an earlier choice comes round),
/// verified against the signed index, and cached per bundle id in Application Support. Until a pack
/// is here, or when it can't be fetched, the base icon stays and the chooser says why.
@MainActor
@Observable
final class CelebrationAssetStore {
    @ObservationIgnored private let source: Source?
    @ObservationIgnored private let policy: PolicyCenter
    @ObservationIgnored private let downloads: CelebrationAssetDownloads
    @ObservationIgnored private let usesRepositoryArtwork: Bool
    @ObservationIgnored private var repositoryIcons: [String: [AppIconVariant: AppIconImagePair]?] = [:]

    /// Where packs come from and the key their index is signed with.
    struct Source {
        let base: URL
        let publicKey: String

        /// A local pack signed with a throwaway key, for checking downloads in a Debug build:
        /// `-celebrationAssetsURL` and `-celebrationAssetsKey`.
        static var override: Source? {
            #if DEBUG
            let defaults = UserDefaults.standard
            if let url = defaults.string(forKey: "celebrationAssetsURL").flatMap(URL.init(string:)),
                let key = defaults.string(forKey: "celebrationAssetsKey")
            {
                return Source(base: url, publicKey: key)
            }
            #endif
            return nil
        }

        /// The latest release's assets, verified with the update key (`SUPublicEDKey`).
        static var release: Source? {
            let info = Bundle.main.infoDictionary ?? [:]
            guard let key = info["SUPublicEDKey"] as? String, !key.isEmpty,
                let repository = AppVersion.current.repository,
                let base = URL(string: "https://github.com/\(repository)/releases/latest/download/")
            else { return nil }
            return Source(base: base, publicKey: key)
        }
    }

    init(
        source: Source? = Source.override ?? Source.release, session: URLSession = .shared,
        policy: PolicyCenter = .shared
    ) {
        self.source = source
        self.policy = policy
        #if DEBUG
        usesRepositoryArtwork = Source.override == nil
        #else
        usesRepositoryArtwork = false
        #endif
        let support = URL.applicationSupportDirectory.appending(path: Bundle.main.bundleIdentifier ?? "Native")
        downloads = CelebrationAssetDownloads(
            configuration: Self.configuration(source: source, policy: policy.policy),
            cache: CelebrationAssetCache(
                root: support.appending(path: "CelebrationAssets", directoryHint: .isDirectory)),
            session: session)
        trackPolicy()
    }

    func state(_ edition: String) -> IconPackState {
        if let icons = repositoryArtwork(edition) { return .ready(icons) }
        return downloads.state(edition)
    }

    func fetch(_ edition: String, retryFailed: Bool = true) {
        downloads.configure(Self.configuration(source: source, policy: policy.policy))
        guard repositoryArtwork(edition) == nil else { return }
        downloads.fetch(edition, retryFailed: retryFailed)
    }

    private func trackPolicy() {
        let configuration = withObservationTracking {
            Self.configuration(source: source, policy: policy.policy)
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in self?.trackPolicy() }
        }
        downloads.configure(configuration)
    }

    private static func configuration(source: Source?, policy: NativePolicy) -> CelebrationAssetDownloads.Configuration
    {
        guard policy.celebrations.downloadsEnabled else { return .unavailable(CelebrationAssetDownloads.disabled) }
        guard let source else { return .unavailable(CelebrationAssetDownloads.cantDownload) }
        return .download(.init(base: policy.celebrations.baseURL ?? source.base, publicKey: source.publicKey))
    }

    /// The edition's renders in `design/app-icon/celebrations`, when this is a Debug build from a
    /// checkout that has them (not Git LFS pointers). Checked once per edition.
    private func repositoryArtwork(_ edition: String) -> [AppIconVariant: AppIconImagePair]? {
        #if DEBUG
        guard usesRepositoryArtwork else { return nil }
        if let known = repositoryIcons[edition] { return known }
        let folder = Self.repository.appending(
            path: "design/app-icon/celebrations/\(edition)", directoryHint: .isDirectory)
        var icons: [AppIconVariant: AppIconImagePair]? = [:]
        for variant in AppIconVariant.allCases {
            let light = folder.appending(path: "\(variant.rawValue)-light.png")
            let dark = folder.appending(path: "\(variant.rawValue)-dark.png")
            guard Self.isImage(light), Self.isImage(dark) else {
                icons = nil
                break
            }
            icons?[variant] = AppIconImagePair(light: .file(light), dark: .file(dark))
        }
        repositoryIcons[edition] = icons
        return icons
        #else
        return nil
        #endif
    }

    #if DEBUG
    /// The checkout this build came from: three folders up from this file.
    private static let repository = URL(filePath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent()

    /// A real PNG, not missing and not a Git LFS pointer ("version https://git-lfs…").
    private static func isImage(_ url: URL) -> Bool {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return false }
        defer { try? handle.close() }
        let head = (try? handle.read(upToCount: 8)) ?? Data()
        return head.starts(with: [0x89, 0x50, 0x4E, 0x47])
    }
    #endif

}
