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
    @ObservationIgnored private let session: URLSession
    @ObservationIgnored private var index: CelebrationAssets.Index?

    /// Where packs come from and the key their index is signed with.
    struct Source {
        let base: URL
        let publicKey: String

        /// The release's assets, verified with the update key (`SUPublicEDKey`). Debug builds can
        /// point at a local pack signed with a throwaway key: `-celebrationAssetsURL` and
        /// `-celebrationAssetsKey`.
        static var current: Source? {
            #if DEBUG
            let defaults = UserDefaults.standard
            if let url = defaults.string(forKey: "celebrationAssetsURL").flatMap(URL.init(string:)),
                let key = defaults.string(forKey: "celebrationAssetsKey")
            {
                return Source(base: url, publicKey: key)
            }
            #endif
            let info = Bundle.main.infoDictionary ?? [:]
            guard let key = info["SUPublicEDKey"] as? String, !key.isEmpty,
                let repository = AppVersion.current.repository,
                let base = URL(string: "https://github.com/\(repository)/releases/latest/download/")
            else { return nil }
            return Source(base: base, publicKey: key)
        }
    }

    init(source: Source? = .current, session: URLSession = .shared) {
        self.source = source
        self.session = session
        let support = URL.applicationSupportDirectory.appending(path: Bundle.main.bundleIdentifier ?? "Native")
        cache = CelebrationAssetCache(root: support.appending(path: "CelebrationAssets", directoryHint: .isDirectory))
    }

    func state(_ edition: String) -> IconPackState {
        _ = generation
        if let icons = cache.icons(for: edition) { return .ready(icons) }
        return states[edition] ?? .notDownloaded
    }

    /// Fetches an edition's pack unless it's here or already on its way.
    func fetch(_ edition: String) {
        switch state(edition) {
        case .ready, .downloading: return
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
        case is Unavailable: "This build of Native can't download celebration icons."
        case URLError.fileDoesNotExist: "The latest release doesn't have these icons yet."
        default: error.localizedDescription
        }
    }

    static let offline = "Downloads when you're online."
}
