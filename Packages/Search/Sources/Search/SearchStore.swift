import Foundation

/// One connection to the index file. The index keeps two, a writer and a reader, so a search never
/// waits behind indexing: the database is in WAL mode, where readers don't block on a writer.
actor SearchStore {
    /// Bumped whenever the schema or what's indexed changes. The index is a cache of transcripts
    /// that live elsewhere, so an old one is dropped and refilled rather than migrated.
    static let schemaVersion = 3

    /// Internal only for SearchStore+Query.swift.
    let database: SQLiteDatabase

    init(path: String) throws {
        database = try SQLiteDatabase(path: path)
        try database.execute(
            """
            PRAGMA journal_mode = WAL;
            PRAGMA synchronous = NORMAL;
            PRAGMA foreign_keys = ON;
            PRAGMA temp_store = MEMORY;
            """)
    }

    // MARK: - Schema

    func prepareSchema() throws {
        var version = 0
        try database.query("PRAGMA user_version") { version = Int($0.int(0)) }
        if version != Self.schemaVersion {
            try dropSchema()
        }
        try database.execute(
            """
            CREATE TABLE IF NOT EXISTS sessions (
                id INTEGER PRIMARY KEY,
                agent TEXT NOT NULL,
                session TEXT NOT NULL,
                title TEXT,
                cwd TEXT NOT NULL,
                project TEXT NOT NULL,
                created_at REAL,
                updated_at REAL,
                archived INTEGER NOT NULL DEFAULT 0,
                UNIQUE (agent, session)
            );
            CREATE INDEX IF NOT EXISTS sessions_project ON sessions (project);
            CREATE INDEX IF NOT EXISTS sessions_updated ON sessions (updated_at);
            CREATE TABLE IF NOT EXISTS items (
                id INTEGER PRIMARY KEY,
                session_row INTEGER NOT NULL REFERENCES sessions (id) ON DELETE CASCADE,
                ordinal INTEGER NOT NULL,
                role TEXT NOT NULL,
                date REAL,
                has_diff INTEGER NOT NULL DEFAULT 0,
                anchor TEXT NOT NULL,
                body TEXT NOT NULL,
                parts TEXT NOT NULL
            );
            CREATE INDEX IF NOT EXISTS items_session ON items (session_row);
            CREATE VIRTUAL TABLE IF NOT EXISTS items_fts USING fts5 (
                body, parts, content = 'items', content_rowid = 'id',
                tokenize = 'unicode61 remove_diacritics 2'
            );
            CREATE TRIGGER IF NOT EXISTS items_inserted AFTER INSERT ON items BEGIN
                INSERT INTO items_fts (rowid, body, parts) VALUES (new.id, new.body, new.parts);
            END;
            CREATE TABLE IF NOT EXISTS sources (
                path TEXT PRIMARY KEY,
                size INTEGER NOT NULL,
                modified REAL NOT NULL,
                offset INTEGER NOT NULL,
                agent TEXT,
                session TEXT,
                cwd TEXT
            );
            CREATE TABLE IF NOT EXISTS meta (key TEXT PRIMARY KEY, value TEXT);
            CREATE TRIGGER IF NOT EXISTS items_deleted AFTER DELETE ON items BEGIN
                INSERT INTO items_fts (items_fts, rowid, body, parts) VALUES ('delete', old.id, old.body, old.parts);
            END;
            PRAGMA user_version = \(Self.schemaVersion);
            """)
    }

    private func dropSchema() throws {
        database.finalizeStatements()
        try database.execute(
            """
            DROP TRIGGER IF EXISTS items_inserted;
            DROP TRIGGER IF EXISTS items_deleted;
            DROP TABLE IF EXISTS items_fts;
            DROP TABLE IF EXISTS items;
            DROP TABLE IF EXISTS sessions;
            DROP TABLE IF EXISTS sources;
            DROP TABLE IF EXISTS meta;
            """)
    }

    // MARK: - Writing

    /// Applies a batch in one transaction: a commit per session would make backfilling thousands
    /// of them slow. Replaced sessions get exactly their documents; appended ones (a history file
    /// that only grew) keep theirs and add the new ones after them.
    func write(_ batch: SearchIndexBatch) throws {
        try database.transaction {
            for entry in batch.replacing {
                let row = try upsert(entry.session)
                try database.query("DELETE FROM items WHERE session_row = ?", [.int(row)])
                var ordinal = 0
                for document in [titleDocument(for: entry.session)] + entry.documents where !document.text.isEmpty {
                    try insert(document, ordinal: ordinal, session: row)
                    ordinal += 1
                }
            }
            for entry in batch.appending {
                let row = try upsert(entry.session)
                var ordinal = 0
                try database.query("SELECT coalesce(max(ordinal), 0) + 1 FROM items WHERE session_row = ?", [.int(row)])
                {
                    ordinal = Int($0.int(0))
                }
                if entry.session.title != nil {
                    try replaceTitle(of: entry.session, row: row)
                }
                for document in entry.documents where !document.text.isEmpty {
                    try insert(document, ordinal: ordinal, session: row)
                    ordinal += 1
                }
            }
            for checkpoint in batch.checkpoints {
                try database.query(
                    """
                    INSERT OR REPLACE INTO sources (path, size, modified, offset, agent, session, cwd)
                    VALUES (?, ?, ?, ?, ?, ?, ?)
                    """,
                    [
                        .text(checkpoint.path), .int(Int64(checkpoint.size)),
                        .double(checkpoint.modifiedAt.timeIntervalSince1970), .int(Int64(checkpoint.offset)),
                        checkpoint.session.map { .text($0.agent) } ?? .null,
                        checkpoint.session.map { .text($0.session) } ?? .null,
                        checkpoint.cwd.map(SQLiteValue.text) ?? .null,
                    ])
            }
        }
    }

    /// Updates what's known about a session without touching its transcript (a rename, an
    /// archive). Does nothing for a session that isn't indexed.
    func update(_ record: SearchSessionRecord) throws {
        try database.transaction {
            guard let row = try sessionRow(record.key) else { return }
            _ = try upsert(record)
            try replaceTitle(of: record, row: row)
        }
    }

    private func replaceTitle(of record: SearchSessionRecord, row: Int64) throws {
        try database.query("DELETE FROM items WHERE session_row = ? AND role = ?", [.int(row), .text("title")])
        let title = titleDocument(for: record)
        if !title.text.isEmpty {
            try insert(title, ordinal: -1, session: row)
        }
    }

    func setArchived(_ key: SearchSessionKey, _ isArchived: Bool) throws {
        try database.query(
            "UPDATE sessions SET archived = ? WHERE agent = ? AND session = ?",
            [SQLiteValue(isArchived), .text(key.agent), .text(key.session)])
    }

    func remove(_ key: SearchSessionKey) throws {
        try database.transaction {
            try database.query(
                "DELETE FROM sessions WHERE agent = ? AND session = ?", [.text(key.agent), .text(key.session)])
        }
    }

    /// Forgets every session that ran in `folder` or below it.
    func removeSessions(under folder: String) throws {
        let prefix = folder.hasSuffix("/") ? folder : folder + "/"
        try database.transaction {
            try database.query(
                "DELETE FROM sessions WHERE cwd = ? OR substr(cwd, 1, ?) = ? OR project = ?",
                [.text(folder), .int(Int64(prefix.count)), .text(prefix), .text(folder)])
        }
    }

    /// Forgets every session last active before `cutoff` (a retention policy).
    func removeSessions(updatedBefore cutoff: Date) throws {
        try database.transaction {
            try database.query(
                "DELETE FROM sessions WHERE coalesce(updated_at, created_at, 0) < ?", [SQLiteValue(cutoff)])
        }
    }

    func removeAll() throws {
        try dropSchema()
        try database.execute("VACUUM")
        try prepareSchema()
    }

    /// How far each history file has been read, by path, and whether its session is still indexed.
    func checkpoints() throws -> [String: HistoryCheckpoint] {
        var checkpoints: [String: HistoryCheckpoint] = [:]
        try database.query(
            """
            SELECT c.path, c.size, c.modified, c.offset, c.agent, c.session, c.cwd, s.id IS NOT NULL
            FROM sources c LEFT JOIN sessions s ON s.agent = c.agent AND s.session = c.session
            """
        ) { row in
            guard let path = row.text(0) else { return }
            let session = row.text(4).flatMap { agent in row.text(5).map { SearchSessionKey(agent: agent, session: $0) }
            }
            checkpoints[path] = HistoryCheckpoint(
                path: path, size: Int(row.int(1)), modifiedAt: row.date(2) ?? .distantPast, offset: Int(row.int(3)),
                session: session, cwd: row.text(6), isSessionIndexed: row.int(7) != 0)
        }
        return checkpoints
    }

    /// Forgets how far the history files of sessions in `folder` were read, so they're read again
    /// (a project no longer excluded).
    func removeCheckpoints(under folder: String) throws {
        let prefix = folder.hasSuffix("/") ? folder : folder + "/"
        try database.query(
            "DELETE FROM sources WHERE cwd = ? OR substr(cwd, 1, ?) = ?",
            [.text(folder), .int(Int64(prefix.count)), .text(prefix)])
    }

    /// Whether a pass over the agents' history has ever finished, so later passes can run at the
    /// lowest priority.
    func isFilled() throws -> Bool {
        var isFilled = false
        try database.query("SELECT 1 FROM meta WHERE key = 'filled'") { _ in isFilled = true }
        return isFilled
    }

    func markFilled() throws {
        try database.query("INSERT OR REPLACE INTO meta (key, value) VALUES ('filled', '1')")
    }

    func statistics() throws -> SearchIndexStatistics {
        var statistics = SearchIndexStatistics()
        try database.query("SELECT count(*) FROM sessions") { statistics.sessions = Int($0.int(0)) }
        try database.query("SELECT count(*) FROM items") { statistics.items = Int($0.int(0)) }
        try database.query("SELECT page_count * page_size FROM pragma_page_count(), pragma_page_size()") {
            statistics.bytes = Int($0.int(0))
        }
        return statistics
    }

    private func upsert(_ record: SearchSessionRecord) throws -> Int64 {
        try database.query(
            """
            INSERT INTO sessions (agent, session, title, cwd, project, created_at, updated_at, archived)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT (agent, session) DO UPDATE SET
                title = coalesce(excluded.title, title), cwd = excluded.cwd, project = excluded.project,
                created_at = coalesce(created_at, excluded.created_at),
                updated_at = coalesce(excluded.updated_at, updated_at), archived = excluded.archived
            """,
            [
                .text(record.key.agent), .text(record.key.session), record.title.map(SQLiteValue.text) ?? .null,
                .text(record.cwd), .text(record.project), SQLiteValue(record.createdAt), SQLiteValue(record.updatedAt),
                SQLiteValue(record.isArchived),
            ])
        guard let row = try sessionRow(record.key) else {
            throw SearchIndexError(code: 0, message: "The session wasn't saved.")
        }
        return row
    }

    private func sessionRow(_ key: SearchSessionKey) throws -> Int64? {
        var row: Int64?
        try database.query(
            "SELECT id FROM sessions WHERE agent = ? AND session = ?", [.text(key.agent), .text(key.session)]
        ) { row = $0.int(0) }
        return row
    }

    private func insert(_ document: SearchDocument, ordinal: Int, session: Int64) throws {
        try database.query(
            """
            INSERT INTO items (session_row, ordinal, role, date, has_diff, anchor, body, parts)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?)
            """,
            [
                .int(session), .int(Int64(ordinal)), .text(document.role.rawValue), SQLiteValue(document.date),
                SQLiteValue(document.hasDiff), .text(document.anchor.stored), .text(document.text),
                .text(SearchText.codeParts(of: document.text)),
            ])
    }

    /// The task's title with its project's name, so either finds it.
    private func titleDocument(for record: SearchSessionRecord) -> SearchDocument {
        let text = [record.title, record.projectName].compactMap { $0 }.filter { !$0.isEmpty }
            .joined(separator: " · ")
        return SearchDocument(role: .title, text: text, anchor: .session, date: record.updatedAt)
    }
}

/// How big the index is.
public struct SearchIndexStatistics: Hashable, Sendable, Codable {
    public var sessions = 0
    public var items = 0
    /// The database file's size.
    public var bytes = 0

    public init(sessions: Int = 0, items: Int = 0, bytes: Int = 0) {
        self.sessions = sessions
        self.items = items
        self.bytes = bytes
    }
}
