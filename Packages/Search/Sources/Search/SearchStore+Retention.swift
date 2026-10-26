import Foundation
import SQLite3

// A retention policy: what it removes, and compacting the file so what it removed is gone from it.
extension SearchStore {
    /// A session's age, as `HistorySession.lastActive` counts it: its newest time, NULL when it has none.
    private static let lastActive = "max(coalesce(updated_at, created_at), coalesce(created_at, updated_at))"

    /// Forgets every session last active before `cutoff`, with its items and their full-text
    /// entries, and every checkpoint that names one. A session with no time is kept: an unknown age
    /// isn't old. Checkpoints of files last changed before the cutoff go too, since a pass skips
    /// those files by their date anyway. What's removed stays in free pages until the next
    /// compaction, so removing anything makes one due.
    func removeSessions(lastActiveBefore cutoff: Date) throws {
        try database.transaction {
            try database.query(
                """
                DELETE FROM sources WHERE modified < ?
                    OR (agent, session) IN (SELECT agent, session FROM sessions WHERE \(Self.lastActive) < ?)
                """, [SQLiteValue(cutoff), SQLiteValue(cutoff)])
            var removed = database.changes
            try database.query("DELETE FROM sessions WHERE \(Self.lastActive) < ?", [SQLiteValue(cutoff)])
            removed += database.changes
            if removed > 0 {
                try database.query("INSERT OR REPLACE INTO meta (key, value) VALUES ('compactionDue', '1')")
            }
        }
    }

    /// Compacts the file when something was removed since the last compaction, at most once a day
    /// since it rewrites the whole file. Returns whether it compacted.
    func compactIfDue(now: Date) throws -> Bool {
        var isDue = false
        var compactedAt: Date?
        try database.query("SELECT key, value FROM meta WHERE key IN ('compactionDue', 'compactedAt')") { row in
            if row.text(0) == "compactedAt" {
                compactedAt = row.date(1)
            } else {
                isDue = true
            }
        }
        guard isDue else { return false }
        // A clock that went back doesn't hold it off.
        if let compactedAt, compactedAt <= now, now.timeIntervalSince(compactedAt) < 86_400 { return false }
        try compact()
        try database.transaction {
            try database.query("DELETE FROM meta WHERE key = 'compactionDue'")
            try database.query("INSERT OR REPLACE INTO meta (key, value) VALUES ('compactedAt', ?)", [SQLiteValue(now)])
        }
        return true
    }

    /// Leaves nothing of deleted rows in the file. The full-text index keeps a deleted row's terms
    /// in older segments until they merge, so it's merged into one first; then the file is
    /// rebuilt without its free pages, and the write-ahead log, which holds old copies of pages,
    /// is emptied.
    private func compact() throws {
        try database.execute("INSERT INTO items_fts (items_fts) VALUES ('optimize')")
        // VACUUM builds the new file in a temporary database, which this connection otherwise keeps
        // in memory, where it would take as much as the whole index.
        try database.execute("PRAGMA temp_store = FILE")
        defer { try? database.execute("PRAGMA temp_store = MEMORY") }
        try database.execute("VACUUM")
        var isBusy = false
        try database.query("PRAGMA wal_checkpoint(TRUNCATE)") { isBusy = $0.int(0) != 0 }
        // A reader kept the log from being emptied; compaction stays due and runs again.
        if isBusy {
            throw SearchIndexError(
                code: SQLITE_BUSY, message: "The search index's log is in use, so it wasn't emptied.")
        }
    }
}
