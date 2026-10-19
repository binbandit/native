import Foundation
import Testing

@testable import Git

@Suite("Clean Up Merged decisions")
struct MergedCleanupTests {
    /// A repository with an `origin`, and Native's task worktree location beside it.
    struct Scenario {
        let test: TestRepository
        let repository: Repository
        let location: URL

        static func make() async throws -> Scenario {
            let test = try await TestRepository.make()
            let base = test.folder.deletingLastPathComponent()
            let remote = base.appending(path: "origin.git", directoryHint: .isDirectory)
            try await test.git("init", "--quiet", "--bare", "--initial-branch=main", remote.path(percentEncoded: false))
            try await test.git("remote", "add", "origin", remote.path(percentEncoded: false))
            try await test.git("push", "--quiet", "--set-upstream", "origin", "main")
            try await test.git("remote", "set-head", "origin", "main")
            let location = base.appending(path: "worktrees/repo", directoryHint: .isDirectory)
            return Scenario(test: test, repository: try await test.repository, location: location)
        }

        /// A task worktree made the way Native makes one, with `commits` commits on its branch.
        @discardableResult
        func task(_ name: String, branch: String? = nil, commits: Int = 1) async throws -> URL {
            let folder = location.appending(path: name, directoryHint: .isDirectory)
            let branch = branch ?? name
            try await repository.addWorktree(at: folder, newBranch: branch)
            try await repository.markProvisional(branch)
            for index in 0..<commits {
                try Data("\(name) \(index)\n".utf8).write(to: folder.appending(path: "\(name)-\(index).txt"))
                try await test.git("add", "--all", in: folder)
                try await test.git("commit", "--quiet", "-m", "\(name) \(index)", in: folder)
            }
            return folder
        }

        func tip(_ branch: String) async throws -> String {
            try await test.git("rev-parse", branch).trimmingCharacters(in: .whitespacesAndNewlines)
        }

        func plan(
            prefix: String = "", lookup: CleanupPullRequestLookup = .found([:])
        ) async throws -> MergedCleanupPlan {
            try await repository.mergedCleanupPlan(
                MergedCleanupOptions(taskLocation: location, branchPrefix: prefix)
            ) { _ in lookup }
        }

        func remove() { test.remove() }
    }

    @Test func aTaskMergedIntoMainQualifiesWithItsBranch() async throws {
        let scenario = try await Scenario.make()
        defer { scenario.remove() }
        let folder = try await scenario.task("fix-login")
        try await scenario.test.git("merge", "--quiet", "--no-ff", "-m", "Merge fix-login", "fix-login")

        let plan = try await scenario.plan()

        #expect(plan.base == "main")
        let worktree = try #require(plan.worktrees.first)
        #expect(plan.worktrees.count == 1)
        #expect(worktree.path.lastPathComponent == folder.lastPathComponent)
        #expect(worktree.reason == .ancestry(base: "main"))
        #expect(worktree.uncommittedFiles == 0)
        #expect((worktree.bytes ?? 0) > 0)
        let branch = try #require(plan.branches.first)
        #expect(branch.name == "fix-login")
        #expect(branch.isNative)
        #expect(branch.checkedOutIn?.lastPathComponent == "fix-login")
    }

    @Test func aSquashMergedPullRequestQualifiesOnlyAtItsHead() async throws {
        let scenario = try await Scenario.make()
        defer { scenario.remove() }
        let folder = try await scenario.task("squashed", branch: "brayden/squashed", commits: 2)
        try await scenario.test.git("push", "--quiet", "--set-upstream", "origin", "brayden/squashed", in: folder)
        try await scenario.test.git("merge", "--quiet", "--squash", "brayden/squashed")
        try await scenario.test.git("commit", "--quiet", "-m", "Squashed (#123)")
        let head = try await scenario.tip("brayden/squashed")
        let merged = CleanupPullRequestLookup.PullRequest(number: 123, headCommit: head, base: "main")

        let recorder = QueryRecorder()
        let plan = try await scenario.repository.mergedCleanupPlan(
            MergedCleanupOptions(taskLocation: scenario.location, branchPrefix: "brayden/")
        ) { queries in
            await recorder.record(queries)
            return .found(["brayden/squashed": [merged]])
        }

        #expect(await recorder.queries.map(\.head) == ["brayden/squashed"])
        #expect(plan.pullRequestCheck == .checked)
        #expect(plan.branches.map(\.reason) == [.pullRequest(number: 123, url: nil, base: "main")])
        #expect(plan.worktrees.map(\.reason) == [.pullRequest(number: 123, url: nil, base: "main")])

        // A commit made after the pull request merged isn't in it, so the branch stays.
        try Data("later\n".utf8).write(to: folder.appending(path: "later.txt"))
        try await scenario.test.git("add", "later.txt", in: folder)
        try await scenario.test.git("commit", "--quiet", "-m", "Later", in: folder)
        let later = try await scenario.repository.mergedCleanupPlan(
            MergedCleanupOptions(taskLocation: scenario.location, branchPrefix: "brayden/")
        ) { _ in .found(["brayden/squashed": [merged]]) }

        #expect(later.branches.isEmpty)
        #expect(later.worktrees.isEmpty)
        #expect(later.kept.map(\.why) == [.changedSincePullRequest(number: 123)])
    }

    @Test func withoutGitHubASquashMergeIsFoundByContent() async throws {
        let scenario = try await Scenario.make()
        defer { scenario.remove() }
        let folder = try await scenario.task("squashed", commits: 2)
        try await scenario.test.git("push", "--quiet", "--set-upstream", "origin", "squashed", in: folder)
        try await scenario.test.git("merge", "--quiet", "--squash", "squashed")
        try await scenario.test.git("commit", "--quiet", "-m", "Squashed")
        try await scenario.task("unmerged", commits: 2)

        let plan = try await scenario.plan(lookup: .unavailable("gh isn't installed."))

        #expect(plan.pullRequestCheck == .unavailable("gh isn't installed."))
        #expect(plan.branches.map(\.name) == ["squashed"])
        #expect(plan.branches.first?.reason == .sameContent(base: "main"))
        #expect(plan.kept.map(\.branch) == ["unmerged"])
        #expect(plan.kept.first?.why == .unmergedCommits(2))
    }

    @Test func unmergedCommitsAndTasksThatNeverCommittedAreKept() async throws {
        let scenario = try await Scenario.make()
        defer { scenario.remove() }
        try await scenario.task("working", commits: 3)
        try await scenario.task("just-started", commits: 0)
        // Main moving on doesn't make an empty task branch "merged".
        try scenario.test.write("main.txt", "more\n")
        try await scenario.test.git("add", "main.txt")
        try await scenario.test.git("commit", "--quiet", "-m", "Main moves on")

        let plan = try await scenario.plan()

        #expect(plan.isEmpty)
        let kept = Dictionary(uniqueKeysWithValues: plan.kept.compactMap { kept in kept.branch.map { ($0, kept.why) } })
        #expect(kept == ["working": .unmergedCommits(3), "just-started": .noCommits])
    }

    @Test func aMergedBranchBroughtBackFromItsArchivedCopyStillQualifies() async throws {
        let scenario = try await Scenario.make()
        defer { scenario.remove() }
        let folder = try await scenario.task("restored")
        try await scenario.test.git("merge", "--quiet", "--no-ff", "-m", "Merge restored", "restored")
        try await scenario.repository.removeWorktree(at: folder)
        try await scenario.repository.archiveBranch("restored")
        try await scenario.repository.restoreArchivedBranch("restored")

        let plan = try await scenario.plan()

        #expect(plan.branches.map(\.name) == ["restored"])
        #expect(plan.branches.first?.isNative == true)
    }

    @Test func protectedAndCurrentBranchesAreNeverOffered() async throws {
        let scenario = try await Scenario.make()
        defer { scenario.remove() }
        for name in ["develop", "release/1.0", "master", "feature"] {
            try await scenario.test.git("branch", name)
        }
        // Merged work on a protected name and on the main checkout's own branch.
        try await scenario.test.git("switch", "--quiet", "feature")
        try scenario.test.write("feature.txt", "feature\n")
        try await scenario.test.git("add", "feature.txt")
        try await scenario.test.git("commit", "--quiet", "-m", "Feature")
        try await scenario.test.git("branch", "--force", "develop", "feature")
        try await scenario.test.git("branch", "--force", "release/1.0", "feature")
        try await scenario.test.git("push", "--quiet", "origin", "feature:main")
        try await scenario.test.git("fetch", "--quiet", "origin")

        let plan = try await scenario.plan(prefix: "")

        #expect(plan.base == "main")
        #expect(plan.branches.isEmpty, "main, develop, release/*, master and the checked-out feature all stay")
    }

    @Test func otherMergedBranchesAreOfferedAsNotNatives() async throws {
        let scenario = try await Scenario.make()
        defer { scenario.remove() }
        try await scenario.test.git("switch", "--quiet", "--create", "someone-elses")
        try scenario.test.write("theirs.txt", "theirs\n")
        try await scenario.test.git("add", "theirs.txt")
        try await scenario.test.git("commit", "--quiet", "-m", "Theirs")
        try await scenario.test.git("switch", "--quiet", "main")
        try await scenario.test.git("merge", "--quiet", "--ff-only", "someone-elses")

        let plan = try await scenario.plan(prefix: "brayden/")

        #expect(plan.branches.map(\.name) == ["someone-elses"])
        #expect(plan.branches.first?.isNative == false)
        #expect(plan.branches.first?.reason == .ancestry(base: "main"))
    }

    @Test func dirtyWorktreesAreListedWithTheirUncommittedFiles() async throws {
        let scenario = try await Scenario.make()
        defer { scenario.remove() }
        let folder = try await scenario.task("dirty")
        try await scenario.test.git("merge", "--quiet", "--ff-only", "dirty")
        try Data("edited\n".utf8).write(to: folder.appending(path: "dirty-0.txt"))
        try Data("new\n".utf8).write(to: folder.appending(path: "untracked.txt"))
        try FileManager.default.createDirectory(
            at: folder.appending(path: "notes", directoryHint: .isDirectory), withIntermediateDirectories: true)
        try Data("deep\n".utf8).write(to: folder.appending(path: "notes/deep.txt"))

        let plan = try await scenario.plan()

        #expect(plan.worktrees.map(\.uncommittedFiles) == [3])
    }

    @Test func staleRecordsAndLeftoverFoldersAreFound() async throws {
        let scenario = try await Scenario.make()
        defer { scenario.remove() }
        // Deleted by hand: git still lists it, as prunable.
        let gone = try await scenario.task("gone")
        try await scenario.test.git("merge", "--quiet", "--ff-only", "gone")
        try FileManager.default.removeItem(at: gone)
        // Forgotten by git but left on disk.
        let leftover = try await scenario.task("leftover", commits: 0)
        let records = try await scenario.test.git("rev-parse", "--git-common-dir").trimmingCharacters(in: .newlines)
        let common = URL(filePath: records, relativeTo: scenario.test.folder)
        try FileManager.default.removeItem(at: common.appending(path: "worktrees/leftover"))
        // Another repository with the same name shares the location; its worktree isn't ours.
        let other = try await TestRepository.make(name: "repo")
        defer { other.remove() }
        try await other.repository.addWorktree(
            at: scenario.location.appending(path: "theirs", directoryHint: .isDirectory), newBranch: "theirs")

        let plan = try await scenario.plan()

        #expect(plan.staleRecords.map(\.path.lastPathComponent) == ["gone"])
        #expect(plan.staleRecords.first?.branch == "gone")
        #expect(plan.leftoverFolders.map(\.path.lastPathComponent) == [leftover.lastPathComponent])
        // The branch the stale record held is merged; it can go once the record does.
        #expect(plan.branches.map(\.name) == ["gone"])
        #expect(plan.branches.first?.checkedOutIn?.lastPathComponent == "gone")
        #expect(plan.worktrees.isEmpty)
    }

    @Test func forgettingOneStaleRecordLeavesTheOthers() async throws {
        let scenario = try await Scenario.make()
        defer { scenario.remove() }
        let first = try await scenario.task("first", commits: 0)
        let second = try await scenario.task("second", commits: 0)
        try FileManager.default.removeItem(at: first)
        try FileManager.default.removeItem(at: second)
        let records = try await scenario.plan().staleRecords
        let firstRecord = try #require(records.first { $0.path.lastPathComponent == "first" })

        try await scenario.repository.forgetStaleWorktree(at: firstRecord.path)

        #expect(try await scenario.plan().staleRecords.map(\.path.lastPathComponent) == ["second"])
        await #expect(throws: GitError.self) {
            try await scenario.repository.forgetStaleWorktree(at: scenario.test.folder)
        }
    }

    @Test func archivedBranchesComeBackWithTheirConfig() async throws {
        let scenario = try await Scenario.make()
        defer { scenario.remove() }
        let folder = try await scenario.task("tracked")
        try await scenario.test.git("push", "--quiet", "--set-upstream", "origin", "tracked", in: folder)
        try await scenario.repository.setNote("nativePullRequest", "https://github.com/o/r/pull/7", on: "tracked")
        let tip = try await scenario.tip("tracked")
        try await scenario.repository.removeWorktree(at: folder)

        try await scenario.repository.archiveBranch("tracked")
        #expect(try await scenario.repository.resolve("refs/heads/tracked") == nil)
        #expect(try await scenario.repository.hasArchivedBranch("tracked"))
        try await scenario.repository.restoreArchivedBranch("tracked")

        #expect(try await scenario.tip("tracked") == tip)
        #expect(try await scenario.repository.isPublished("tracked"))
        #expect(try await scenario.repository.notes("nativePullRequest")["tracked"] != nil)
        #expect(try await scenario.repository.hasArchivedBranch("tracked") == false)
    }
}

/// Collects what the planner asked GitHub.
private actor QueryRecorder {
    private(set) var queries: [CleanupPullRequestLookup.Query] = []

    func record(_ queries: [CleanupPullRequestLookup.Query]) {
        self.queries += queries
    }
}
