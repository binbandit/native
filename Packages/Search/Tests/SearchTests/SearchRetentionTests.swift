import Foundation
import Testing

@testable import Search

/// What a retention policy removes from the index, and what it must leave.
struct SearchRetentionTests {
    let now = Date(timeIntervalSince1970: 1_790_000_000)
    let url = URL.temporaryDirectory.appending(path: "search-retention-\(UUID().uuidString)/index.sqlite")

    private func record(_ id: String, daysAgo: Double?, createdDaysAgo: Double? = nil) -> SearchSessionRecord {
        SearchSessionRecord(
            key: SearchSessionKey(agent: "claude-code", session: id), title: "Task \(id)", cwd: "/code/native",
            createdAt: createdDaysAgo.map(ago), updatedAt: daysAgo.map(ago))
    }

    private func ago(_ days: Double) -> Date {
        now.addingTimeInterval(-days * 86_400)
    }

    private func checkpoint(_ path: String, session: String?, modifiedDaysAgo: Double) -> HistoryCheckpoint {
        HistoryCheckpoint(
            path: path, size: 10, modifiedAt: ago(modifiedDaysAgo), offset: 10,
            session: session.map { SearchSessionKey(agent: "claude-code", session: $0) }, cwd: "/code/native")
    }

    private func entry(_ record: SearchSessionRecord, text: String = "deploy the worker") -> SearchIndexEntry {
        SearchIndexEntry(session: record, documents: [SearchDocument(role: .user, text: text, anchor: .session)])
    }

    private func indexed(_ index: SearchIndex) async throws -> Set<String> {
        let results = try await index.search(SearchQuery("deploy worker is:archived"), now: now)
        return Set(results.groups.map(\.session.key.session))
    }

    @Test func aSessionWithNoTimeIsKept() async throws {
        let index = try await SearchIndex(url: url)
        try await index.write(
            SearchIndexBatch(replacing: [
                entry(record("unknown", daysAgo: nil)), entry(record("created-only", daysAgo: nil, createdDaysAgo: 90)),
                entry(record("recent", daysAgo: 2)), entry(record("resumed", daysAgo: 40, createdDaysAgo: 2)),
            ]))
        try await index.removeSessions(lastActiveBefore: ago(30))
        let kept = try await indexed(index)
        // Unknown age isn't old; otherwise a session is as old as its newest time.
        #expect(kept == ["unknown", "recent", "resumed"])
    }

    @Test func historyAgeIsItsNewestTime() {
        func session(created: Date?, updated: Date?) -> HistorySession {
            HistorySession(sessionID: "s", title: nil, cwd: "/", createdAt: created, updatedAt: updated, documents: [])
        }
        #expect(session(created: nil, updated: nil).lastActive == nil)
        #expect(session(created: ago(90), updated: nil).lastActive == ago(90))
        #expect(session(created: ago(2), updated: ago(40)).lastActive == ago(2))
    }

    @Test func retentionRemovesTheCheckpointsOfWhatItRemoves() async throws {
        let index = try await SearchIndex(url: url)
        try await index.write(
            SearchIndexBatch(
                replacing: [entry(record("old", daysAgo: 90)), entry(record("recent", daysAgo: 2))],
                checkpoints: [
                    // Touched recently, but its session's last activity is old.
                    checkpoint("/h/old.jsonl", session: "old", modifiedDaysAgo: 1),
                    checkpoint("/h/recent.jsonl", session: "recent", modifiedDaysAgo: 2),
                    // A file with no conversation, unchanged since before the cutoff.
                    checkpoint("/h/commands.jsonl", session: nil, modifiedDaysAgo: 60),
                ]))
        try await index.removeSessions(lastActiveBefore: ago(30))
        let left = try await Set(index.checkpoints().keys)
        #expect(left == ["/h/recent.jsonl"])
    }

    @Test func removedTextLeavesTheFile() async throws {
        let index = try await SearchIndex(url: url)
        let secret = "Quokkamarmalade"
        try await index.write(
            SearchIndexBatch(replacing: [
                entry(record("old", daysAgo: 90), text: "deploy \(secret) worker"), entry(record("recent", daysAgo: 2)),
            ]))
        try await index.removeSessions(lastActiveBefore: ago(30))
        #expect(try await indexed(index) == ["recent"])
        // Deleting alone leaves the text in free pages and the log.
        #expect(try fileContains(secret))
        #expect(try await index.compactIfDue(now: now))
        #expect(try !fileContains(secret))
        #expect(try await indexed(index) == ["recent"])
        // Nothing removed since: nothing to do.
        #expect(try await !index.compactIfDue(now: now.addingTimeInterval(2 * 86_400)))
    }

    @Test func compactionRunsAtMostOnceADay() async throws {
        let index = try await SearchIndex(url: url)
        try await index.write(
            SearchIndexBatch(replacing: [entry(record("a", daysAgo: 40)), entry(record("b", daysAgo: 20))]))
        // Nothing removed, nothing due.
        try await index.removeSessions(lastActiveBefore: ago(60))
        #expect(try await !index.compactIfDue(now: now))

        try await index.removeSessions(lastActiveBefore: ago(30))
        #expect(try await index.compactIfDue(now: now))
        try await index.removeSessions(lastActiveBefore: ago(10))
        // Due, and waits out the day; a clock that went back doesn't hold it off.
        #expect(try await !index.compactIfDue(now: now.addingTimeInterval(3_600)))
        #expect(try await index.compactIfDue(now: now.addingTimeInterval(-3_600)))
        try await index.write(SearchIndexBatch(replacing: [entry(record("c", daysAgo: 20))]))
        try await index.removeSessions(lastActiveBefore: ago(10))
        #expect(try await index.compactIfDue(now: now.addingTimeInterval(86_400)))
        #expect(try await indexed(index).isEmpty)
    }

    /// Whether the index's file or its write-ahead log still holds `text`, in any case.
    private func fileContains(_ text: String) throws -> Bool {
        let needles = [text, text.lowercased()].map { Data($0.utf8) }
        for suffix in ["", "-wal"] {
            guard let data = FileManager.default.contents(atPath: url.path(percentEncoded: false) + suffix) else {
                continue
            }
            if needles.contains(where: { data.range(of: $0) != nil }) { return true }
        }
        return false
    }
}
