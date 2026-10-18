import Foundation
import Testing

@testable import Search

/// Reads this Mac's real Claude Code and Codex history into a throwaway index and times queries,
/// printing counts and timings only, never transcript text. Off unless `SEARCH_REAL_HISTORY=1`.
struct RealHistoryCheck {
    @Test(.enabled(if: ProcessInfo.processInfo.environment["SEARCH_REAL_HISTORY"] != nil))
    func indexesAndSearchesRealHistory() async throws {
        let url = URL.temporaryDirectory.appending(path: "search-real-\(UUID().uuidString)/index.sqlite")
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let index = try await SearchIndex(url: url)
        let readers: [(String, any SessionHistoryReader)] = [
            ("claude-code", ClaudeCodeHistoryReader.standard()), ("codex", CodexHistoryReader.standard()),
        ]
        for (agent, reader) in readers {
            let started = Date.now
            let sources = reader.sources()
            var sessions = 0, documents = 0, failures = 0, empty = 0
            var readTime: TimeInterval = 0
            var batch: [SearchIndexEntry] = []
            for source in sources {
                let readStarted = Date.now
                do {
                    guard let session = try reader.read(source) else {
                        empty += 1
                        continue
                    }
                    readTime += Date.now.timeIntervalSince(readStarted)
                    sessions += 1
                    documents += session.documents.count
                    batch.append(
                        SearchIndexEntry(
                            session: SearchSessionRecord(
                                key: SearchSessionKey(agent: agent, session: session.sessionID), title: session.title,
                                cwd: session.cwd, createdAt: session.createdAt, updatedAt: session.updatedAt),
                            documents: session.documents, source: source.stamp))
                    if batch.count >= 25 {
                        try await index.replace(batch)
                        batch = []
                    }
                } catch {
                    failures += 1
                }
            }
            try await index.replace(batch)
            let bytes = sources.reduce(0) { $0 + $1.size }
            print(
                "\(agent): \(sources.count) files (\(bytes / 1_000_000) MB), \(sessions) sessions, \(empty) without a conversation, \(failures) failed, \(documents) documents; read \(Int(readTime))s, total \(Int(Date.now.timeIntervalSince(started)))s"
            )
        }
        print("index: \(try await index.statistics())")
        let queries = [
            "the reference app now has the ability", "native/Models/SessionCatalog.swift", "swift format lint --strict",
            "SessionCatalog", "catalog", "xcodebuild", "rollb", "agent:codex test", "role:user search",
        ]
        for text in queries {
            var best = Double.infinity
            var results = SearchResults.empty
            for _ in 0..<5 {
                results = try await index.search(SearchQuery(text))
                best = min(best, results.duration)
            }
            let roles = results.groups.first?.hits.map(\.role.rawValue).joined(separator: ",") ?? "-"
            print("query [\(text)]: \(results.groups.count) tasks, best hit roles \(roles), \(Int(best * 1000)) ms")
        }
    }
}
