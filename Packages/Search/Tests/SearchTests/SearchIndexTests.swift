import Foundation
import Testing

@testable import Search

struct SearchIndexTests {
    let now = Date(timeIntervalSince1970: 1_790_000_000)

    private func makeIndex() async throws -> SearchIndex {
        let url = URL.temporaryDirectory.appending(path: "search-\(UUID().uuidString)/index.sqlite")
        return try await SearchIndex(url: url)
    }

    private func session(
        _ id: String, agent: String = "claude-code", title: String, project: String = "/code/native",
        daysAgo: Double = 1,
        archived: Bool = false
    ) -> SearchSessionRecord {
        SearchSessionRecord(
            key: SearchSessionKey(agent: agent, session: id), title: title, cwd: project, project: project,
            updatedAt: now.addingTimeInterval(-daysAgo * 86_400), isArchived: archived)
    }

    private func seed(_ index: SearchIndex) async throws {
        try await index.replace(
            session("s1", title: "Fix flaky login timeout"),
            documents: [
                SearchDocument(
                    role: .user, text: "Why does the login page hang after a timeout?",
                    anchor: .message(probe: "Why does")),
                SearchDocument(
                    role: .thought, text: "Maybe the refresh token expires", anchor: .message(probe: "Maybe")),
                SearchDocument(
                    role: .tool, text: "Edit\n/code/native/native/Models/SessionStore.swift\nloginTimeout = 30",
                    anchor: .toolCall(id: "toolu_1"), hasDiff: true),
                SearchDocument(
                    role: .agent, text: "Raised the login timeout to 30s.", anchor: .message(probe: "Raised")),
            ])
        try await index.replace(
            session("s2", agent: "codex", title: "Orders migration rollback", project: "/code/orders", daysAgo: 30),
            documents: [
                SearchDocument(role: .user, text: "Write a migration rollback plan", anchor: .message(probe: "Write")),
                SearchDocument(
                    role: .tool, text: "exec_command\ncargo test -p orders\ntest result: ok",
                    anchor: .toolCall(id: "call_1")),
            ])
        try await index.replace(
            session("s3", title: "Old login work", daysAgo: 400, archived: true),
            documents: [SearchDocument(role: .user, text: "The login timeout again", anchor: .message(probe: "The"))])
    }

    @Test func findsAPhraseAndGroupsHitsByTask() async throws {
        let index = try await makeIndex()
        try await seed(index)
        let results = try await index.search(SearchQuery("login timeout "), now: now)
        #expect(results.groups.map(\.session.key.session) == ["s1"])
        let group = try #require(results.groups.first)
        #expect(group.hits.count == 3)
        #expect(group.hits.allSatisfy { $0.role != .thought })
        #expect(group.hits.first?.snippet.runs.contains { $0.isMatch } == true)
    }

    @Test func findsPathsCommandsAndIdentifierParts() async throws {
        let index = try await makeIndex()
        try await seed(index)
        let path = try await index.search(SearchQuery("SessionStore.swift"), now: now)
        #expect(path.groups.first?.hits.first?.anchor == .toolCall(id: "toolu_1"))
        let command = try await index.search(SearchQuery("cargo test -p orders"), now: now)
        #expect(command.groups.map(\.session.key.session) == ["s2"])
        let part = try await index.search(SearchQuery("store "), now: now)
        #expect(part.groups.first?.hits.first?.snippet.runs.contains { $0.isMatch && $0.text == "Store" } == true)
        let prefix = try await index.search(SearchQuery("rollb"), now: now)
        #expect(prefix.groups.map(\.session.key.session) == ["s2"])
    }

    @Test func filtersNarrowResults() async throws {
        let index = try await makeIndex()
        try await seed(index)
        let archived = try await index.search(SearchQuery("login is:archived"), now: now)
        #expect(Set(archived.groups.map(\.session.key.session)) == ["s1", "s3"])
        let codex = try await index.search(SearchQuery("agent:codex"), now: now)
        #expect(codex.groups.map(\.session.key.session) == ["s2"])
        let diffs = try await index.search(SearchQuery("login has:diff"), now: now)
        #expect(diffs.groups.first?.hits.map(\.role) == [.tool])
        let thinking = try await index.search(SearchQuery("refresh role:thinking"), now: now)
        #expect(thinking.groups.first?.hits.map(\.role) == [.thought])
        let project = try await index.search(
            SearchQuery("migration", filters: SearchFilters(projects: ["/code/native"])), now: now)
        #expect(project.groups.isEmpty)
    }

    @Test func titlesAndProjectsAreSearchable() async throws {
        let index = try await makeIndex()
        try await seed(index)
        let byProject = try await index.search(SearchQuery("orders "), now: now)
        #expect(byProject.groups.first?.session.key.session == "s2")
        try await index.update(session("s2", agent: "codex", title: "Renamed task", project: "/code/orders"))
        let renamed = try await index.search(SearchQuery("renamed "), now: now)
        #expect(renamed.groups.first?.hits.first?.role == .title)
    }

    @Test func recentTasksRankFirst() async throws {
        let index = try await makeIndex()
        try await index.replace(
            session("old", title: "a", daysAgo: 300),
            documents: [SearchDocument(role: .agent, text: "deploy the worker", anchor: .session)])
        try await index.replace(
            session("new", title: "b", daysAgo: 0),
            documents: [SearchDocument(role: .agent, text: "deploy the worker", anchor: .session)])
        let results = try await index.search(SearchQuery("deploy worker "), now: now)
        #expect(results.groups.map(\.session.key.session) == ["new", "old"])
    }

    @Test func forgettingAProjectAndEverything() async throws {
        let index = try await makeIndex()
        try await seed(index)
        try await index.removeSessions(under: "/code/orders")
        #expect(try await index.search(SearchQuery("migration "), now: now).groups.isEmpty)
        try await index.removeAll()
        #expect(try await index.statistics().sessions == 0)
        #expect(try await index.search(SearchQuery("login "), now: now).groups.isEmpty)
    }

    @Test func retentionForgetsOldSessions() async throws {
        let index = try await makeIndex()
        try await seed(index)
        try await index.removeSessions(updatedBefore: now.addingTimeInterval(-60 * 86_400))
        let results = try await index.search(SearchQuery("login is:archived"), now: now)
        #expect(results.groups.map(\.session.key.session) == ["s1"])
        #expect(try await index.statistics().sessions == 2)
    }

    @Test func checkpointsAndAppends() async throws {
        let index = try await makeIndex()
        let key = SearchSessionKey(agent: "claude-code", session: "s1")
        let checkpoint = HistoryCheckpoint(
            path: "/h/a.jsonl", size: 10, modifiedAt: now, offset: 8, session: key, cwd: "/code/native")
        try await index.write(
            SearchIndexBatch(
                replacing: [
                    SearchIndexEntry(
                        session: session("s1", title: "First"),
                        documents: [SearchDocument(role: .user, text: "first turn", anchor: .session)])
                ], checkpoints: [checkpoint]))
        try await index.write(
            SearchIndexBatch(appending: [
                SearchIndexEntry(
                    session: SearchSessionRecord(key: key, cwd: "/code/native", updatedAt: now),
                    documents: [SearchDocument(role: .agent, text: "second turn", anchor: .session)])
            ]))
        let results = try await index.search(SearchQuery("turn "), now: now)
        #expect(results.groups.first?.hitCount == 2)
        // Appending without a title keeps the one it had.
        #expect(results.groups.first?.session.title == "First")
        let stored = try #require(try await index.checkpoints()["/h/a.jsonl"])
        #expect(stored.offset == 8 && stored.isSessionIndexed)
        #expect(
            stored.resume(for: HistorySource(url: URL(filePath: "/h/a.jsonl"), size: 20, modifiedAt: now))?.offset == 8)
        // A file that shrank was rewritten: read it from the start.
        #expect(stored.resume(for: HistorySource(url: URL(filePath: "/h/a.jsonl"), size: 4, modifiedAt: now)) == nil)

        try await index.removeSessions(updatedBefore: now.addingTimeInterval(86_400))
        #expect(try await index.checkpoints()["/h/a.jsonl"]?.isSessionIndexed == false)
        #expect(try await index.isFilled() == false)
        try await index.markFilled()
        #expect(try await index.isFilled())
    }

    /// `SEARCH_BENCH=1 swift test --filter benchmark`: a few thousand sessions, timed queries.
    @Test(.enabled(if: ProcessInfo.processInfo.environment["SEARCH_BENCH"] != nil))
    func benchmark() async throws {
        let index = try await makeIndex()
        let vocabulary =
            (0..<4_000).map { "word\($0)" } + ["timeout", "migration", "SessionStore", "refactor", "deploy"]
        var generator = SystemRandomNumberGenerator()
        let started = Date.now
        var partsTime: TimeInterval = 0
        for batch in stride(from: 0, to: 3_000, by: 25) {
            let entries = (batch..<batch + 25).map { sessionNumber in
                let documents = (0..<60).map { position in
                    let words = (0..<40).map { _ in vocabulary.randomElement(using: &generator) ?? "" }
                    return SearchDocument(
                        role: [.user, .agent, .tool][position % 3], text: words.joined(separator: " "), anchor: .session
                    )
                }
                return SearchIndexEntry(
                    session: session(
                        "s\(sessionNumber)", title: "Task \(sessionNumber)", project: "/code/p\(sessionNumber % 20)",
                        daysAgo: Double(sessionNumber % 365)),
                    documents: documents)
            }
            let partsStarted = Date.now
            for entry in entries { for document in entry.documents { _ = SearchText.codeParts(of: document.text) } }
            partsTime += Date.now.timeIntervalSince(partsStarted)
            try await index.write(SearchIndexBatch(replacing: entries))
        }
        print("code parts took \(partsTime)s")
        print("indexed 180k items in \(Date.now.timeIntervalSince(started))s, \(try await index.statistics())")
        for text in [
            "timeout", "word12 word99", "SessionStore", "store", "dep", "\"word1 word2\"", "timeout agent:claude",
        ] {
            var best = Double.infinity
            for _ in 0..<5 {
                let results = try await index.search(SearchQuery(text), now: now)
                best = min(best, results.duration)
            }
            print("query \(text): \(Int(best * 1000)) ms")
        }
    }
}
