import Foundation
import Observation

/// The download model shared by the chooser and automatic celebration selection. All requests for
/// celebration artwork go through one configurable source; disabling it leaves cached icons usable.
@MainActor
@Observable
public final class CelebrationAssetDownloads {
    public struct Source: Equatable, Sendable {
        public let base: URL
        public let publicKey: String

        public init(base: URL, publicKey: String) {
            self.base = base
            self.publicKey = publicKey
        }
    }

    public enum Configuration: Equatable, Sendable {
        case download(Source)
        case unavailable(String)
    }

    public static let offline = "Downloads when you're online."
    public static let disabled = "Icon downloads are disabled by policy. Your current icon stays as it is."
    public static let cantDownload = "Icons can't download in this build of Native. Your current icon stays as it is."

    private var configuration: Configuration
    private var states: [String: IconPackState] = [:]
    private var generation = 0
    @ObservationIgnored private let cache: CelebrationAssetCache
    @ObservationIgnored private let session: URLSession
    @ObservationIgnored private var index: CelebrationAssets.Index?
    @ObservationIgnored private var tasks: [String: Task<Void, Never>] = [:]

    public init(configuration: Configuration, cache: CelebrationAssetCache, session: URLSession = .shared) {
        self.configuration = configuration
        self.cache = cache
        self.session = session
    }

    /// Cancels in-flight requests when policy changes, before another endpoint can be contacted.
    public func configure(_ configuration: Configuration) {
        guard self.configuration != configuration else { return }
        for task in tasks.values { task.cancel() }
        tasks.removeAll()
        index = nil
        states.removeAll()
        self.configuration = configuration
    }

    public func state(_ edition: String) -> IconPackState {
        _ = generation
        if let icons = cache.icons(for: edition) { return .ready(icons) }
        if case .unavailable(let reason) = configuration { return .unavailable(reason) }
        return states[edition] ?? .notDownloaded
    }

    @discardableResult
    public func fetch(_ edition: String, retryFailed: Bool = true) -> Task<Void, Never>? {
        switch state(edition) {
        case .ready, .downloading, .unavailable: return nil
        case .failed where !retryFailed: return nil
        case .notDownloaded, .failed: break
        }
        guard case .download(let source) = configuration else { return nil }
        states[edition] = .downloading
        let task = Task {
            do {
                let pack = try await download(edition, source: source)
                try Task.checkCancellation()
                try cache.store(pack)
                states[edition] = nil
                generation += 1
            } catch {
                // A cancelled request belongs to the old policy, never the new state.
                guard !Task.isCancelled else { return }
                index = nil
                states[edition] = .failed(Self.message(for: error))
            }
            tasks[edition] = nil
        }
        tasks[edition] = task
        return task
    }

    private func download(_ edition: String, source: Source) async throws -> CelebrationAssets.Pack {
        if index?.packs[edition] == nil {
            let indexURL = source.base.appending(path: CelebrationAssets.indexName)
            async let data = load(indexURL)
            async let signature = load(indexURL.appendingPathExtension("sig"))
            let verified = try await CelebrationAssets.verifiedIndex(
                data, signature: String(decoding: signature, as: UTF8.self), publicKey: source.publicKey)
            try Task.checkCancellation()
            index = verified
        }
        guard let index, let entry = index.packs[edition] else { throw CelebrationAssets.Failure.notInIndex(edition) }
        try Task.checkCancellation()
        let data = try await load(source.base.appending(path: entry.file))
        return try CelebrationAssets.verifiedPack(data, edition: edition, index: index)
    }

    private func load(_ url: URL) async throws -> Data {
        try Task.checkCancellation()
        let (data, response) = try await session.data(from: url)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw URLError(.fileDoesNotExist)
        }
        return data
    }

    private static func message(for error: any Error) -> String {
        switch error {
        case let error as URLError
        where [.notConnectedToInternet, .networkConnectionLost, .timedOut, .cannotFindHost, .dataNotAllowed]
            .contains(error.code):
            offline
        case URLError.fileDoesNotExist: "The latest release doesn't have these icons yet."
        case let error as CelebrationAssets.Failure: error.localizedDescription
        default: "These icons couldn't download. Your current icon stays as it is."
        }
    }
}
