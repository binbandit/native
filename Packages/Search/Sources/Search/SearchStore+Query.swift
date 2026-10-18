import Foundation

// Answering queries: full-text matches ranked by relevance, recency and who said it, grouped
// by task.
extension SearchStore {
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
    /// How many of the best text matches are weighed by recency and role, without filters.
    static let weighedMatchLimit = 4_000

    fileprivate func searchText(
        _ expression: String, parsed: ParsedSearchQuery, query: SearchQuery, now: Date
    ) throws
        -> SearchResults
    {
        var (conditions, bindings) = filterClauses(parsed, includeItems: true)
        // A word that's everywhere ("the") matches most of the index, and weighing every match by
        // recency and role means a lookup each. Without narrowing filters, only the best matches
        // by text alone are weighed; filters must see every match, or they'd miss rarer ones.
        let matches =
            parsed.isNarrowed
            ? "SELECT rowid AS id, bm25(items_fts, 1.0, 0.4) AS relevance FROM items_fts WHERE items_fts MATCH ?"
            : """
            SELECT rowid AS id, bm25(items_fts, 1.0, 0.4) AS relevance FROM items_fts WHERE items_fts MATCH ?
            ORDER BY relevance LIMIT \(Self.weighedMatchLimit)
            """
        bindings.insert(.text(expression), at: 0)
        // bm25 is negative, more so for better matches. Recent sessions and the user's own words
        // weigh more; reasoning and tool output, which repeat everything, weigh less.
        let sql = """
            SELECT i.id, i.session_row, i.role, i.anchor, i.date, i.has_diff
            FROM (\(matches)) m
            JOIN items i ON i.id = m.id
            JOIN sessions s ON s.id = i.session_row
            \(conditions.isEmpty ? "" : "WHERE " + conditions.joined(separator: " AND "))
            ORDER BY m.relevance
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
        let prefixes = parsed.prefixWords
        let groups = sessionRows.compactMap { row -> SearchGroup? in
            guard let session = sessions[row] else { return nil }
            let hits = (hitsBySession[row] ?? []).map { hit in
                SearchHit(
                    id: hit.id, role: hit.role, anchor: hit.anchor, date: hit.date, hasDiff: hit.hasDiff,
                    snippet: SearchSnippet(text: bodies[hit.id] ?? "", words: words, prefixes: prefixes))
            }
            return SearchGroup(session: session, hits: hits, hitCount: counts[row] ?? hits.count)
        }
        return SearchResults(groups: groups, isTruncated: ranked > Self.rankedHitLimit || order.count > query.limit)
    }

    /// With only filters and no text: the latest sessions that pass them.
    fileprivate func recentSessions(parsed: ParsedSearchQuery, limit: Int) throws -> SearchResults {
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

    fileprivate func filterClauses(_ parsed: ParsedSearchQuery, includeItems: Bool) -> ([String], [SQLiteValue]) {
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

    fileprivate func records(_ rows: [Int64]) throws -> [Int64: SearchSessionRecord] {
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

    fileprivate func bodies(of items: [Int64]) throws -> [Int64: String] {
        guard !items.isEmpty else { return [:] }
        var bodies: [Int64: String] = [:]
        let placeholders = Array(repeating: "?", count: items.count).joined(separator: ", ")
        try database.query("SELECT id, body FROM items WHERE id IN (\(placeholders))", items.map(SQLiteValue.int)) {
            bodies[$0.int(0)] = $0.text(1)
        }
        return bodies
    }
}
