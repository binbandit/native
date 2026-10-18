import Foundation

/// One connection to the index file. The index keeps two, a writer and a reader, so a search never
/// waits behind indexing: the database is in WAL mode, where readers don't block on a writer.
actor SearchStore {
    /// Bumped whenever the schema or what's indexed changes. The index is a cache of transcripts
    /// that live elsewhere, so an old one is dropped and refilled rather than migrated.
    static let schemaVersion = 1

    private let database: SQLiteDatabase

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
                source_path TEXT,
                source_stamp TEXT,
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
                tokenize = 'unicode61 remove_diacritics 2', prefix = '2 3'
            );
            CREATE TRIGGER IF NOT EXISTS items_inserted AFTER INSERT ON items BEGIN
                INSERT INTO items_fts (rowid, body, parts) VALUES (new.id, new.body, new.parts);
            END;
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
            """)
    }

    // MARK: - Writing

    /// Puts `record` and its documents in place of whatever the index had for the session.
    func replace(_ record: SearchSessionRecord, documents: [SearchDocument], source: SearchSourceStamp?) throws {
        try database.transaction {
            let row = try upsert(record, source: source)
            try database.query("DELETE FROM items WHERE session_row = ?", [.int(row)])
            var ordinal = 0
            for document in [titleDocument(for: record)] + documents where !document.text.isEmpty {
                try insert(document, ordinal: ordinal, session: row)
                ordinal += 1
            }
        }
    }

    /// Updates what's known about a session without touching its transcript (a rename, an
    /// archive). Does nothing for a session that isn't indexed.
    func update(_ record: SearchSessionRecord) throws {
        try database.transaction {
            guard let row = try sessionRow(record.key) else { return }
            _ = try upsert(record, source: nil)
            try database.query("DELETE FROM items WHERE session_row = ? AND role = ?", [.int(row), .text("title")])
            let title = titleDocument(for: record)
            if !title.text.isEmpty {
                try insert(title, ordinal: -1, session: row)
            }
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

    func removeAll() throws {
        try dropSchema()
        try database.execute("VACUUM")
        try prepareSchema()
    }

    /// The stamp each indexed history file had when it was read, by path.
    func sourceStamps() throws -> [String: String] {
        var stamps: [String: String] = [:]
        try database.query("SELECT source_path, source_stamp FROM sessions WHERE source_path IS NOT NULL") { row in
            if let path = row.text(0), let stamp = row.text(1) {
                stamps[path] = stamp
            }
        }
        return stamps
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

    private func upsert(_ record: SearchSessionRecord, source: SearchSourceStamp?) throws -> Int64 {
        try database.query(
            """
            INSERT INTO sessions (agent, session, title, cwd, project, created_at, updated_at, archived,
                source_path, source_stamp)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT (agent, session) DO UPDATE SET
                title = excluded.title, cwd = excluded.cwd, project = excluded.project,
                created_at = coalesce(excluded.created_at, created_at),
                updated_at = coalesce(excluded.updated_at, updated_at), archived = excluded.archived,
                source_path = coalesce(excluded.source_path, source_path),
                source_stamp = coalesce(excluded.source_stamp, source_stamp)
            """,
            [
                .text(record.key.agent), .text(record.key.session), record.title.map(SQLiteValue.text) ?? .null,
                .text(record.cwd), .text(record.project), SQLiteValue(record.createdAt), SQLiteValue(record.updatedAt),
                SQLiteValue(record.isArchived), source.map { .text($0.path) } ?? .null,
                source.map { .text($0.stamp) } ?? .null,
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

    // MARK: - Reading

    func search(_ query: SearchQuery, now: Date) throws -> SearchResults {
        let started = Date.now
        let parsed = ParsedSearchQuery(query)
        var results =
            if let expression = parsed.expression {
                try searchText(expression, parsed: parsed, query: query, now: now)
            } else {
                try recentSessions(parsed: parsed, limit: query.limit)
            }
        results.duration = Date.now.timeIntervalSince(started)
        return results
    }

    /// How many hits are ranked before grouping; past this, counts are lower bounds.
    static let rankedHitLimit = 600

    private func searchText(_ expression: String, parsed: ParsedSearchQuery, query: SearchQuery, now: Date) throws
        -> SearchResults
    {
        var (conditions, bindings) = filterClauses(parsed, includeItems: true)
        conditions.insert("items_fts MATCH ?", at: 0)
        bindings.insert(.text(expression), at: 0)
        // bm25 is negative, more so for better matches. Recent sessions and the user's own words
        // weigh more; reasoning and tool output, which repeat everything, weigh less.
        let sql = """
            SELECT i.id, i.session_row, i.role, i.anchor, i.date, i.has_diff
            FROM items_fts
            JOIN items i ON i.id = items_fts.rowid
            JOIN sessions s ON s.id = i.session_row
            WHERE \(conditions.joined(separator: " AND "))
            ORDER BY bm25(items_fts, 1.0, 0.4)
                * (1.0 + 0.5 / (1.0 + max(0.0, ? - coalesce(i.date, s.updated_at, 0)) / 1209600.0))
                * CASE i.role WHEN 'title' THEN 1.5 WHEN 'user' THEN 1.25 WHEN 'agent' THEN 1.0
                    WHEN 'plan' THEN 1.0 WHEN 'tool' THEN 0.8 ELSE 0.6 END
            LIMIT ?
            """
        bindings += [.double(now.timeIntervalSince1970), .int(Int64(Self.rankedHitLimit + 1))]

        struct RankedHit {
            var id: Int64
            var role: SearchRole
            var anchor: SearchAnchor
            var date: Date?
            var hasDiff: Bool
        }
        var order: [Int64] = []
        var hitsBySession: [Int64: [RankedHit]] = [:]
        var counts: [Int64: Int] = [:]
        var ranked = 0
        try database.query(sql, bindings) { row in
            ranked += 1
            guard ranked <= Self.rankedHitLimit else { return }
            let session = row.int(1)
            if counts[session] == nil {
                order.append(session)
            }
            counts[session, default: 0] += 1
            guard hitsBySession[session, default: []].count < query.hitsPerSession else { return }
            hitsBySession[session, default: []].append(
                RankedHit(
                    id: row.int(0), role: SearchRole(rawValue: row.text(2) ?? "") ?? .agent,
                    anchor: SearchAnchor(stored: row.text(3) ?? ""), date: row.date(4), hasDiff: row.int(5) != 0))
        }
        let sessionRows = Array(order.prefix(query.limit))
        let sessions = try records(sessionRows)
        let shownHits = sessionRows.flatMap { hitsBySession[$0] ?? [] }
        let bodies = try bodies(of: shownHits.map(\.id))
        let words = parsed.highlightWords
        let groups = sessionRows.compactMap { row -> SearchGroup? in
            guard let session = sessions[row] else { return nil }
            let hits = (hitsBySession[row] ?? []).map { hit in
                SearchHit(
                    id: hit.id, role: hit.role, anchor: hit.anchor, date: hit.date, hasDiff: hit.hasDiff,
                    snippet: SearchSnippet(text: bodies[hit.id] ?? "", words: words))
            }
            return SearchGroup(session: session, hits: hits, hitCount: counts[row] ?? hits.count)
        }
        return SearchResults(groups: groups, isTruncated: ranked > Self.rankedHitLimit || order.count > query.limit)
    }

    /// With only filters and no text: the latest sessions that pass them.
    private func recentSessions(parsed: ParsedSearchQuery, limit: Int) throws -> SearchResults {
        let (conditions, bindings) = filterClauses(parsed, includeItems: false)
        let filter = conditions.isEmpty ? "" : "WHERE " + conditions.joined(separator: " AND ")
        var rows: [Int64] = []
        try database.query(
            "SELECT s.id FROM sessions s \(filter) ORDER BY s.updated_at DESC LIMIT ?",
            bindings + [.int(Int64(limit + 1))]
        ) { rows.append($0.int(0)) }
        let sessions = try records(Array(rows.prefix(limit)))
        let groups = rows.prefix(limit).compactMap { row in
            sessions[row].map { SearchGroup(session: $0, hits: [], hitCount: 0) }
        }
        return SearchResults(groups: groups, isTruncated: rows.count > limit)
    }

    private func filterClauses(_ parsed: ParsedSearchQuery, includeItems: Bool) -> ([String], [SQLiteValue]) {
        let filters = parsed.filters
        var conditions: [String] = []
        var bindings: [SQLiteValue] = []
        func any(_ column: String, in values: some Collection<String>) {
            guard !values.isEmpty else { return }
            conditions.append("\(column) IN (\(Array(repeating: "?", count: values.count).joined(separator: ", ")))")
            bindings += values.sorted().map(SQLiteValue.text)
        }
        any("s.agent", in: filters.agents)
        any("s.project", in: filters.projects)
        for name in parsed.agentNames {
            conditions.append("instr(lower(s.agent), ?) > 0")
            bindings.append(.text(name.lowercased()))
        }
        for name in parsed.projectNames {
            conditions.append("instr(lower(s.project), ?) > 0")
            bindings.append(.text(name.lowercased()))
        }
        if !filters.includeArchived {
            conditions.append("s.archived = 0")
        }
        let date = includeItems ? "coalesce(i.date, s.updated_at)" : "s.updated_at"
        if let after = filters.after {
            conditions.append("\(date) >= ?")
            bindings.append(SQLiteValue(after))
        }
        if let before = filters.before {
            conditions.append("\(date) < ?")
            bindings.append(SQLiteValue(before))
        }
        guard includeItems else {
            if filters.hasDiff {
                conditions.append("EXISTS (SELECT 1 FROM items d WHERE d.session_row = s.id AND d.has_diff = 1)")
            }
            return (conditions, bindings)
        }
        if !filters.roles.isEmpty {
            any("i.role", in: filters.roles.map(\.rawValue))
        } else if !filters.includeThinking {
            conditions.append("i.role != 'thought'")
        }
        if filters.hasDiff {
            conditions.append("i.has_diff = 1")
        }
        return (conditions, bindings)
    }

    private func records(_ rows: [Int64]) throws -> [Int64: SearchSessionRecord] {
        guard !rows.isEmpty else { return [:] }
        var records: [Int64: SearchSessionRecord] = [:]
        let placeholders = Array(repeating: "?", count: rows.count).joined(separator: ", ")
        try database.query(
            """
            SELECT id, agent, session, title, cwd, project, created_at, updated_at, archived
            FROM sessions WHERE id IN (\(placeholders))
            """, rows.map(SQLiteValue.int)
        ) { row in
            records[row.int(0)] = SearchSessionRecord(
                key: SearchSessionKey(agent: row.text(1) ?? "", session: row.text(2) ?? ""), title: row.text(3),
                cwd: row.text(4) ?? "", project: row.text(5), createdAt: row.date(6), updatedAt: row.date(7),
                isArchived: row.int(8) != 0)
        }
        return records
    }

    private func bodies(of items: [Int64]) throws -> [Int64: String] {
        guard !items.isEmpty else { return [:] }
        var bodies: [Int64: String] = [:]
        let placeholders = Array(repeating: "?", count: items.count).joined(separator: ", ")
        try database.query("SELECT id, body FROM items WHERE id IN (\(placeholders))", items.map(SQLiteValue.int)) {
            bodies[$0.int(0)] = $0.text(1)
        }
        return bodies
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
