import ACP
import Testing

struct DetectedTurnChangesTests {
    typealias File = TurnSummary.ChangedFile

    @Test func shellOnlyChangesSupplyFilesWithoutAnEditTool() {
        let files = [File(path: "/repo/README.md", added: 2), File(path: "/repo/new.txt", added: 1)]
        #expect(File.merging(reported: [], detected: files, pathKey: { $0 }) == files)
    }

    @Test func netCountsReplaceToolCountsAndShellFilesFollowReportedOnes() {
        let files = File.merging(
            reported: [.init(path: "README.md", added: 12, removed: 4)],
            detected: [.init(path: "new.txt", added: 1), .init(path: "README.md", added: 2, removed: 1)],
            pathKey: { $0 })
        #expect(files == [.init(path: "README.md", added: 2, removed: 1), .init(path: "new.txt", added: 1)])
    }

    @Test func equivalentPathsCountTheNetChangeOnceAndKeepTheReportedSpelling() {
        let files = File.merging(
            reported: [.init(path: "README.md", added: 4), .init(path: "/repo/README.md", added: 3)],
            detected: [.init(path: "/repo/README.md", added: 2)],
            pathKey: { $0.hasPrefix("/repo/") ? String($0.dropFirst(6)) : $0 })
        #expect(files == [.init(path: "README.md", added: 2)])
    }

    @Test func missingDetectionsKeepUndoneAndOutsideRepositoryEdits() {
        let reported = [File(path: "undone.txt", added: 3), File(path: "/outside/notes.txt", removed: 1)]
        #expect(File.merging(reported: reported, detected: [], pathKey: { $0 }) == reported)
    }

    @Test func anEditedFileRenamedByTheShellHasOneRow() {
        let files = File.merging(
            reported: [.init(path: "old.txt", added: 4)], detected: [.init(path: "new.txt", added: 2)],
            pathKey: { $0 == "old.txt" ? "new.txt" : $0 })
        #expect(files == [.init(path: "old.txt", added: 2)])
    }

    @Test func equivalentReportedPathsWithoutDetectionKeepTheirAccumulatedCounts() {
        let files = File.merging(
            reported: [.init(path: "a.txt", added: 2), .init(path: "/repo/a.txt", added: 1, removed: 1)],
            detected: [], pathKey: { $0.hasPrefix("/repo/") ? String($0.dropFirst(6)) : $0 })
        #expect(files == [.init(path: "a.txt", added: 3, removed: 1)])
    }

    @Test func binaryChangesRemainVisibleWithoutLineCounts() {
        let files = [File(path: "image.png")]
        #expect(File.merging(reported: [], detected: files, pathKey: { $0 }) == files)
        #expect(File.merging(reported: [], detected: [], pathKey: { $0 }).isEmpty)
    }
}
