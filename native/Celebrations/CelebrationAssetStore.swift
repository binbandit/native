import AppAppearance
import Foundation
import Observation

/// Native's celebration icons that download instead of shipping in the app: fetched from the latest
/// release when someone chooses a celebration (or a week before an earlier choice comes round),
/// verified against the signed index, and cached per bundle id in Application Support. Until a pack
/// is here, or when it can't be fetched, the base icon stays and the chooser says why.
@MainActor
@Observable
final class CelebrationAssetStore {
    /// Packs on their way or that failed; a cached pack is read from disk instead.
    private(set) var states: [String: IconPackState] = [:]
    /// Bumped when a pack lands, so anything showing its state looks again.
    private(set) var generation = 0

    @ObservationIgnored let cache: CelebrationAssetCache
    @ObservationIgnored private let source: Source?
    /// Debug builds use the repository's artwork as if it were downloaded, so celebrations work
    /// from source with no release; an explicit `-celebrationAssetsURL` turns that off.
    @ObservationIgnored private let usesRepositoryArtwork: Bool
    @ObservationIgnored private var repositoryIcons: [String: [AppIconVariant: AppIconImagePair]?] = [:]
    @ObservationIgnored private let session: URLSession
    @ObservationIgnored private var index: CelebrationAssets.Index?

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

    init(source: Source? = Source.override ?? Source.release, session: URLSession = .shared) {
        self.source = source
        self.session = session
        #if DEBUG
        usesRepositoryArtwork = Source.override == nil
        #else
        usesRepositoryArtwork = false
        #endif
        let support = URL.applicationSupportDirectory.appending(path: Bundle.main.bundleIdentifier ?? "Native")
        cache = CelebrationAssetCache(root: support.appending(path: "CelebrationAssets", directoryHint: .isDirectory))
    }

    func state(_ edition: String) -> IconPackState {
        _ = generation
        if let icons = repositoryArtwork(edition) ?? cache.icons(for: edition) { return .ready(icons) }
        if let state = states[edition] { return state }
        return source == nil ? .unavailable(Self.cantDownload) : .notDownloaded
    }

    /// The edition's renders in `design/app-icon/celebrations`, when this is a Debug build from a
    /// checkout that has them (not Git LFS pointers). Checked once per edition.
    private func repositoryArtwork(_ edition: String) -> [AppIconVariant: AppIconImagePair]? {
        #if DEBUG
        guard usesRepositoryArtwork else { return nil }
        if let known = repositoryIcons[edition] { return known }
        let folder = Self.repository.appending(path: "design/app-icon/celebrations/\(edition)", directoryHint: .isDirectory)
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

    /// Fetches an edition's pack unless it's here or already on its way.
    func fetch(_ edition: String) {
        switch state(edition) {
        case .ready, .downloading, .unavailable: return
        case .notDownloaded, .failed: break
        }
        states[edition] = .downloading
        Task {
            do {
                let pack = try await download(edition)
                try cache.store(pack)
                states[edition] = nil
                generation += 1
            } catch {
                states[edition] = .failed(Self.message(for: error))
            }
        }
    }

    private func download(_ edition: String) async throws -> CelebrationAssets.Pack {
        guard let source else { throw Unavailable() }
        if index?.packs[edition] == nil {
            let indexURL = source.base.appending(path: CelebrationAssets.indexName)
            async let data = load(indexURL)
            async let signature = load(indexURL.appendingPathExtension("sig"))
            index = try await CelebrationAssets.verifiedIndex(
                data, signature: String(decoding: signature, as: UTF8.self), publicKey: source.publicKey)
        }
        guard let index, let entry = index.packs[edition] else { throw CelebrationAssets.Failure.notInIndex(edition) }
        let data = try await load(source.base.appending(path: entry.file))
        return try CelebrationAssets.verifiedPack(data, edition: edition, index: index)
    }

    private func load(_ url: URL) async throws -> Data {
        let (data, response) = try await session.data(from: url)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw URLError(.fileDoesNotExist)
        }
        return data
    }

    private struct Unavailable: Error {}

    /// What the chooser says: offline is a normal state, not an error.
    private static func message(for error: any Error) -> String {
        switch error {
        case let error as URLError
        where [.notConnectedToInternet, .networkConnectionLost, .timedOut, .cannotFindHost, .dataNotAllowed]
            .contains(error.code):
            offline
        case is Unavailable: cantDownload
        case URLError.fileDoesNotExist: "The latest release doesn't have these icons yet."
        default: error.localizedDescription
        }
    }

    static let offline = "Downloads when you're online."
    static let cantDownload =
        "Icons can't download in this build of Native. You can still choose it; the icon changes once its icons are available."
}
