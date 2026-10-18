import Foundation

/// The full-text index of every agent session: SQLite FTS5 in one file, written by the indexer and
/// queried by search, each on its own connection so neither waits for the other.
///
/// It's a cache of transcripts that live with the agents, so it can be cleared at any time and
/// refills from them.
public final class SearchIndex: Sendable {
    public let url: URL
    private let writer: SearchStore
    private let reader: SearchStore

    /// Opens (or creates) the index at `url`, dropping one made by an incompatible build.
    public init(url: URL) async throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        self.url = url
        let path = url.path(percentEncoded: false)
        writer = try SearchStore(path: path)
        try await writer.prepareSchema()
        reader = try SearchStore(path: path)
    }

    /// The default location: `Application Support/<bundle id>/search-index.sqlite`.
    public static func defaultURL(bundleIdentifier: String?) -> URL {
        URL.applicationSupportDirectory.appending(path: bundleIdentifier ?? "Native", directoryHint: .isDirectory)
            .appending(path: "search-index.sqlite")
    }

    // MARK: - Indexing

    /// Indexes a session's transcript, replacing what was indexed for it before.
    public func replace(_ session: SearchSessionRecord, documents: [SearchDocument]) async throws {
        try await writer.write(SearchIndexBatch(replacing: [SearchIndexEntry(session: session, documents: documents)]))
    }

    /// Applies a batch of writes in one transaction, for backfilling.
    public func write(_ batch: SearchIndexBatch) async throws {
        guard !batch.isEmpty else { return }
        try await writer.write(batch)
    }

    /// Updates a session's title, project or dates, leaving its transcript as indexed.
    public func update(_ session: SearchSessionRecord) async throws {
        try await writer.update(session)
    }

    public func setArchived(_ key: SearchSessionKey, _ isArchived: Bool) async throws {
        try await writer.setArchived(key, isArchived)
    }

    public func remove(_ key: SearchSessionKey) async throws {
        try await writer.remove(key)
    }

    /// Forgets every session that ran in `folder` or below it (a project excluded from search).
    public func removeSessions(under folder: String) async throws {
        try await writer.removeSessions(under: folder)
    }

    /// Forgets every session last active before `cutoff`, for a retention policy.
    public func removeSessions(updatedBefore cutoff: Date) async throws {
        try await writer.removeSessions(updatedBefore: cutoff)
    }

    /// Forgets everything and gives the space back.
    public func removeAll() async throws {
        try await writer.removeAll()
    }

    /// How far each history file has been read, by path.
    public func checkpoints() async throws -> [String: HistoryCheckpoint] {
        try await writer.checkpoints()
    }

    /// Reads the history files of sessions in `folder` again on the next pass.
    public func removeCheckpoints(under folder: String) async throws {
        try await writer.removeCheckpoints(under: folder)
    }

    /// Whether a pass over the agents' history has ever finished.
    public func isFilled() async throws -> Bool {
        try await writer.isFilled()
    }

    public func markFilled() async throws {
        try await writer.markFilled()
    }

    public func statistics() async throws -> SearchIndexStatistics {
        try await reader.statistics()
    }

    // MARK: - Searching

    public func search(_ query: SearchQuery, now: Date = .now) async throws -> SearchResults {
        try await reader.search(query, now: now)
    }
}
