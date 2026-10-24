import Foundation
import Testing

@testable import ApprovalAnalysis

@Suite struct UnknownCommandCountsTests {
    @Test func localCountsAreBoundedPrivateAndPurgeable() async throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appending(path: "counts.json")
        let store = UnknownCommandCounts(url: url)
        try await store.record(program: "internal-tool", enabled: false)
        #expect(!FileManager.default.fileExists(atPath: url.path))
        for unsafe in ["/secret/path/tool", "tool --token secret", "\nsecret", "", ".private", "x@example.com"] {
            try await store.record(program: unsafe, enabled: true)
        }
        #expect(!FileManager.default.fileExists(atPath: url.path))
        try await store.record(program: "internal-tool", enabled: true)
        try await store.record(program: "internal-tool", enabled: true)
        try await store.record(program: "another-tool", enabled: true)
        let top = try await UnknownCommandCounts(url: url).top()
        #expect(top == [.init(program: "internal-tool", count: 2), .init(program: "another-tool", count: 1)])
        let json = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [[String: Any]])
        #expect(json.allSatisfy { Set($0.keys) == ["program", "count"] })
        for index in 0..<260 { try await store.record(program: "tool\(index)", enabled: true) }
        #expect(try await store.top(limit: 1000).count == 256)
        try await store.purge()
        #expect(!FileManager.default.fileExists(atPath: url.path))
        #expect(try await store.top().isEmpty)
    }

    @Test func damagedOrUnwritableStoreCannotBreakApproval() async throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appending(path: "counts.json")
        try Data("bad data".utf8).write(to: url)
        let store = UnknownCommandCounts(url: url)
        await #expect(throws: UnknownCommandCounts.Failure.invalid) {
            try await store.record(program: "tool", enabled: true)
        }
        try await store.purge()
        try await store.record(program: "tool", enabled: true)
        let blocked = UnknownCommandCounts(url: url.appending(path: "not-a-directory/counts.json"))
        await #expect(throws: UnknownCommandCounts.Failure.unwritable) {
            try await blocked.record(program: "tool", enabled: true)
        }
    }

    @Test func unknownNamesExcludeArgumentsAndPaths() {
        func unknown(_ text: String) -> String? {
            ApprovalCommand(command: text, workingDirectory: "/repo").unknownProgram
        }
        #expect(unknown("internal-tool --token secret") == "internal-tool")
        #expect(unknown("/internal/path/tool --token secret") == nil)
        #expect(unknown("internal-tool && other") == nil)
        #expect(unknown("git unknown-command") == nil)
        #expect(unknown("git status --unknown-flag") == nil)
    }
}
