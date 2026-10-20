import Foundation
import NativeHostProtocol
import Synchronization
import Testing

@testable import NativeHost

#if os(macOS)
import NativeHostMac
#endif

@Suite("Watching folders on a host", .timeLimit(.minutes(1)))
struct FileWatchingTests {
    @Test(
        "Changes go out at once after a quiet spell, then at most once a window, merged, and past the limit as an overflow"
    )
    func coalescing() async throws {
        let sent = Recorded<[String]>()
        let latency = Duration.milliseconds(300)
        let coalescer = FileChangeCoalescer(latency: latency, limit: 3) { paths, isOverflow in
            sent.append(isOverflow ? ["overflow"] : paths)
        }
        coalescer.add(FileWatchBatch(paths: ["a"]))
        #expect(sent.values == [["a"]])

        coalescer.add(FileWatchBatch(paths: ["c", "b"]))
        coalescer.add(FileWatchBatch(paths: ["b"]))
        #expect(sent.values.count == 1, "held for the rest of the window")
        try await pollUntil("the window to close") { sent.values.count == 2 }
        #expect(sent.values.last == ["b", "c"])

        coalescer.add(FileWatchBatch(paths: ["1", "2"]))
        coalescer.add(FileWatchBatch(paths: ["3", "4"]))
        try await pollUntil("the overflow") { sent.values.count == 3 }
        #expect(sent.values.last == ["overflow"])

        try await Task.sleep(for: latency + .milliseconds(100))
        coalescer.add(FileWatchBatch(paths: ["quiet"]))
        #expect(sent.values.last == ["quiet"])

        coalescer.add(FileWatchBatch(paths: ["late"]))
        coalescer.stop()
        try await Task.sleep(for: latency + .milliseconds(100))
        #expect(sent.values.count == 4, "nothing goes out once stopped")
    }

    @Test(
        "A walk notices files added, changed and removed, never folders for their timestamps, and never follows links")
    func snapshots() throws {
        let folder = try scratchFolder()
        defer { try? FileManager.default.removeItem(atPath: folder) }
        let manager = FileManager.default
        try manager.createDirectory(atPath: folder + "/sub", withIntermediateDirectories: true)
        try Data("one".utf8).write(to: URL(filePath: folder + "/kept.txt"))
        try Data("x".utf8).write(to: URL(filePath: folder + "/gone.txt"))
        try manager.createSymbolicLink(atPath: folder + "/system", withDestinationPath: "/usr")

        let before = FolderSnapshot(root: folder, entryLimit: 1_000)
        #expect(before.entries.keys.contains(folder + "/system"))
        #expect(!before.entries.keys.contains { $0.hasPrefix(folder + "/system/") })
        #expect(before.changes(to: FolderSnapshot(root: folder, entryLimit: 1_000)) == nil)

        try Data("one, longer".utf8).write(to: URL(filePath: folder + "/kept.txt"))
        try manager.removeItem(atPath: folder + "/gone.txt")
        try Data("new".utf8).write(to: URL(filePath: folder + "/sub/new.txt"))
        let after = FolderSnapshot(root: folder, entryLimit: 1_000)
        #expect(
            before.changes(to: after)?.paths == [folder + "/gone.txt", folder + "/kept.txt", folder + "/sub/new.txt"])

        // Where a truncated walk stops moves, so it can only say that something changed.
        let truncated = FolderSnapshot(root: folder, entryLimit: 2)
        try Data("more".utf8).write(to: URL(filePath: folder + "/more.txt"))
        #expect(
            truncated.changes(to: FolderSnapshot(root: folder, entryLimit: 2))
                == FileWatchBatch(paths: [], isOverflow: true))
    }

    @Test("Polling reports a new file")
    func polling() async throws {
        try await expectNewFileReported(by: PollingFileWatching(interval: .milliseconds(100)))
    }

    #if os(macOS)
    @Test("FSEvents reports a new file")
    func fsEvents() async throws {
        try await expectNewFileReported(by: FSEventsFileWatching(latency: 0.05))
    }
    #endif

    private func expectNewFileReported(by watching: any FileWatching) async throws {
        let folder = try scratchFolder()
        defer { try? FileManager.default.removeItem(atPath: folder) }
        let heard = Recorded<FileWatchBatch>()
        let following = Task {
            for await batch in watching.changes(under: folder) {
                heard.append(batch)
            }
        }
        // Both watchers start from what's there once they're running.
        try await Task.sleep(for: .milliseconds(300))
        try Data("new".utf8).write(to: URL(filePath: folder + "/new.txt"))
        try await pollUntil("the new file") { heard.values.flatMap(\.paths).contains(folder + "/new.txt") }
        following.cancel()
    }

    /// An empty folder, with symbolic links resolved as the host's paths are.
    private func scratchFolder() throws -> String {
        let url = FileManager.default.temporaryDirectory.appending(path: "watching-\(UUID().uuidString.prefix(8))")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return try #require(ProjectPaths.resolvedPath(url.path(percentEncoded: false)))
    }
}
