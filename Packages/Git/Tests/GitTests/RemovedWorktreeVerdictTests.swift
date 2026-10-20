import Foundation
import Testing

@testable import Git

/// Tasks whose worktrees were removed outside Native: done when their work is merged or their
/// branch is gone, kept in sight when their branch still has work of its own.
@Suite("Worktrees removed outside Native")
struct RemovedWorktreeVerdictTests {
    @Test func aMergedBranchMeansTheTaskIsDone() async throws {
        let task = try await RemovedTask.make()
        defer { task.test.remove() }
        try await task.commit()
        try await task.test.git("merge", "--quiet", "--no-ff", "-m", "Merge", task.branch)
        try await task.removeWithGit()

        #expect(try await task.verdict() == .done(.merged(branch: task.branch, .ancestry(base: "main"))))
    }

    @Test func aSquashMergedBranchMeansTheTaskIsDone() async throws {
        let task = try await RemovedTask.make()
        defer { task.test.remove() }
        try await task.commit()
        try await task.test.git("merge", "--quiet", "--squash", task.branch)
        try await task.test.git("commit", "--quiet", "-m", "Squashed")
        try await task.removeWithGit()

        #expect(try await task.verdict() == .done(.merged(branch: task.branch, .sameContent(base: "main"))))
    }

    @Test func unmergedWorkKeepsTheTaskInSight() async throws {
        let task = try await RemovedTask.make()
        defer { task.test.remove() }
        try await task.commit()
        try await task.removeWithGit()

        #expect(try await task.verdict() == .unmerged(branch: task.branch, why: .unmergedCommits(1)))
    }

    @Test func aBranchThatNeverCommittedMeansTheTaskIsDone() async throws {
        let task = try await RemovedTask.make()
        defer { task.test.remove() }
        try await task.removeWithGit()

        #expect(try await task.verdict() == .done(.noCommits(branch: task.branch)))
    }

    @Test(arguments: [false, true])
    func aDeletedBranchMeansTheTaskIsDone(keepingACopy: Bool) async throws {
        let task = try await RemovedTask.make()
        defer { task.test.remove() }
        try await task.commit()
        try await task.removeWithGit()
        if keepingACopy {
            try await task.test.repository.archiveBranch(task.branch)
        } else {
            try await task.test.git("branch", "--quiet", "-D", task.branch)
        }

        #expect(try await task.verdict() == .done(.branchGone))
    }

    @Test func aFolderDeletedWithoutAPruneIsTiedByGitsRecord() async throws {
        // A branch named nothing like its folder: only git's record ties them.
        let task = try await RemovedTask.make(folder: "zz999", branch: "feature/search")
        defer { task.test.remove() }
        try await task.commit()
        try FileManager.default.removeItem(at: task.path)

        #expect(try await task.verdict() == .unmerged(branch: "feature/search", why: .unmergedCommits(1)))
    }

    @Test func twoBranchesTheTitleCouldMeanAreLeftToTheUser() async throws {
        let task = try await RemovedTask.make(folder: "q1w2e", branch: "a/search")
        defer { task.test.remove() }
        try await task.test.git("branch", "b/search")
        try await task.removeWithGit()

        #expect(try await task.verdict(title: "Search") == .unknownBranch(["a/search", "b/search"]))
    }
}

/// A task worktree in a folder named after its provisional branch's code, as Native makes them.
private struct RemovedTask {
    let test: TestRepository
    let path: URL
    let branch: String

    static func make(folder: String = "ab3c4", branch: String? = nil) async throws -> RemovedTask {
        let test = try await TestRepository.make()
        let location = test.folder.deletingLastPathComponent().appending(path: "worktrees", directoryHint: .isDirectory)
        let requested = location.appending(path: folder, directoryHint: .isDirectory)
        let branch = branch ?? "me/\(folder)"
        try await test.git("worktree", "add", "--quiet", "-b", branch, requested.path(percentEncoded: false))
        // As git spells it (`/private/var/…`).
        let toplevel = try await test.git("rev-parse", "--show-toplevel", in: requested)
        let path = URL(filePath: toplevel.trimmingCharacters(in: .whitespacesAndNewlines), directoryHint: .isDirectory)
        return RemovedTask(test: test, path: path, branch: branch)
    }

    func commit() async throws {
        try Data("work\n".utf8).write(to: path.appending(path: "work.txt"))
        try await test.git("add", "work.txt", in: path)
        try await test.git("commit", "--quiet", "-m", "Work", in: path)
    }

    func removeWithGit() async throws {
        try await test.git("worktree", "remove", "--force", path.path(percentEncoded: false))
    }

    func verdict(title: String? = nil) async throws -> RemovedWorktreeVerdict? {
        let options = MergedCleanupOptions(taskLocation: path.deletingLastPathComponent(), branchPrefix: "me/")
        return try await test.repository.removedWorktreeVerdicts(
            for: [RemovedWorktreeTask(path: path, title: title)], options: options,
            pullRequests: { _ in .unavailable("No GitHub in tests") }
        ).first
    }
}
