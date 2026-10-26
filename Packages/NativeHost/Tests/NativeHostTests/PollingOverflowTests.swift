import Foundation
import Testing

@testable import NativeHost

@Suite("Capped polling snapshots", .timeLimit(.minutes(1)))
struct PollingOverflowTests {
    @Test("An edit beyond an unchanged scanned prefix still overflows")
    func unobservedEdit() throws {
        let root = try pollingOverflowTree()
        defer { try? FileManager.default.removeItem(atPath: root) }
        let before = FolderSnapshot(root: root, entryLimit: 2)
        try Data("edited leaf contents".utf8).write(to: URL(filePath: root + "/sub/leaf"))
        let after = FolderSnapshot(root: root, entryLimit: 2)

        #expect(before.isTruncated && after.isTruncated)
        #expect(Set(before.entries.keys) == Set([root, root + "/sub"]))
        #expect(before.entries == after.entries)
        #expect(before.changes(to: after) == FileWatchBatch(paths: [], isOverflow: true))
    }

    @Test("Entering and leaving incomplete coverage both overflow")
    func coverageTransitions() throws {
        let root = try pollingOverflowTree()
        defer { try? FileManager.default.removeItem(atPath: root) }
        let truncated = FolderSnapshot(root: root, entryLimit: 2)
        try FileManager.default.removeItem(atPath: root + "/sub/leaf")
        let complete = FolderSnapshot(root: root, entryLimit: 2)

        #expect(truncated.isTruncated)
        #expect(!complete.isTruncated)
        #expect(truncated.changes(to: complete) == FileWatchBatch(paths: [], isOverflow: true))
        #expect(complete.changes(to: truncated) == FileWatchBatch(paths: [], isOverflow: true))
    }

    @Test("Complete walks stay quiet when unchanged and report exact sorted additions, edits and deletions")
    func completeSnapshots() throws {
        let root = try pollingOverflowTree()
        defer { try? FileManager.default.removeItem(atPath: root) }
        try Data("gone".utf8).write(to: URL(filePath: root + "/gone"))
        let before = FolderSnapshot(root: root, entryLimit: 10)
        #expect(!before.isTruncated)
        #expect(before.changes(to: FolderSnapshot(root: root, entryLimit: 10)) == nil)

        try Data("longer leaf contents".utf8).write(to: URL(filePath: root + "/sub/leaf"))
        try FileManager.default.removeItem(atPath: root + "/gone")
        for name in ["z", "a"] {
            try Data("added".utf8).write(to: URL(filePath: root + "/" + name))
        }
        let after = FolderSnapshot(root: root, entryLimit: 10)
        #expect(!after.isTruncated)
        #expect(
            before.changes(to: after)
                == FileWatchBatch(paths: [root + "/a", root + "/gone", root + "/sub/leaf", root + "/z"]))
    }

    @Test("A capped polling stream overflows before and after an unseen edit")
    func pollingStream() async throws {
        let root = try pollingOverflowTree()
        defer { try? FileManager.default.removeItem(atPath: root) }
        try await withThrowingTaskGroup(of: Void.self) { group in
            group.addTask {
                var received = 0
                let changes = await PollingFileWatching(interval: .milliseconds(20), entryLimit: 2).changes(under: root)
                for await batch in changes {
                    #expect(batch == FileWatchBatch(paths: [], isOverflow: true))
                    received += 1
                    if received == 2 { return }
                    // The first overflow proves polling is ready before editing the unobserved leaf.
                    try Data("edited while polling".utf8).write(to: URL(filePath: root + "/sub/leaf"))
                }
                #expect(Task.isCancelled, "The watcher ended before reporting both overflows")
            }
            group.addTask {
                try await Task.sleep(for: .seconds(5))
                Issue.record("Timed out waiting for capped polling overflows")
            }
            defer { group.cancelAll() }
            try await group.next()
        }
    }

    private func pollingOverflowTree() throws -> String {
        let url = FileManager.default.temporaryDirectory.appending(path: "polling-overflow-\(UUID())")
        try FileManager.default.createDirectory(at: url.appending(path: "sub"), withIntermediateDirectories: true)
        try Data("leaf".utf8).write(to: url.appending(path: "sub/leaf"))
        return try #require(ProjectPaths.resolvedPath(url.path(percentEncoded: false)))
    }
}
