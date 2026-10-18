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

    /// Indexes a session's transcript, replacing what was indexed for it before. `source` is the
    /// history file it was read from, if any, so an unchanged file isn't read again.
    public func replace(
        _ session: SearchSessionRecord, documents: [SearchDocument], source: SearchSourceStamp? = nil
    ) async throws {
        try await writer.replace(session, documents: documents, source: source)
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

    /// Forgets everything and gives the space back.
    public func removeAll() async throws {
        try await writer.removeAll()
    }

    /// The stamp each indexed history file had when it was read, by path.
    public func sourceStamps() async throws -> [String: String] {
        try await writer.sourceStamps()
    }

    public func statistics() async throws -> SearchIndexStatistics {
        try await reader.statistics()
    }

    // MARK: - Searching

    public func search(_ query: SearchQuery, now: Date = .now) async throws -> SearchResults {
        try await reader.search(query, now: now)
    }
}
