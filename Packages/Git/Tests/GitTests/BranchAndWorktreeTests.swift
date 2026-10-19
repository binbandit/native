import Foundation
import Synchronization
import Testing

@testable import Git

@Suite("Branches, pushing and worktrees")
struct BranchAndWorktreeTests {
    /// A repository with a bare repository next to it as `origin`; pushing to a local path keeps
    /// the test off the network.
    private func repositoryWithRemote() async throws -> (TestRepository, URL) {
        let test = try await TestRepository.make()
        let remote = test.folder.deletingLastPathComponent().appending(path: "origin.git", directoryHint: .isDirectory)
        try await test.git("init", "--quiet", "--bare", "--initial-branch=main", remote.path(percentEncoded: false))
        try await test.git("remote", "add", "origin", remote.path(percentEncoded: false))
        return (test, remote)
    }

    @Test func pushSetsTheUpstreamThenTracksAheadAndBehind() async throws {
        let (test, _) = try await repositoryWithRemote()
        defer { test.remove() }
        let repository = try await test.repository

        try await repository.push()
        var branch = try await repository.status().branch
        #expect(branch.upstream == "origin/main")
        #expect(branch.ahead == 0)

        try test.write("more.txt", "more\n")
        try await repository.commit(message: "More", files: try await repository.status().changes)
        branch = try await repository.status().branch
        #expect(branch.ahead == 1)
        #expect(branch.behind == 0)

        try await repository.push()
        #expect(try await repository.status().branch.ahead == 0)

        try await test.git("reset", "--quiet", "--hard", "HEAD~1")
        branch = try await repository.status().branch
        #expect(branch.behind == 1)
    }

    @Test func pushWithoutARemoteOrBranchFails() async throws {
        let test = try await TestRepository.make()
        defer { test.remove() }
        let repository = try await test.repository

        await #expect(throws: GitError.noRemote) { try await repository.push() }
        #expect(GitError.noRemote.failure == .noRemote)

        try await test.git("checkout", "--quiet", "--detach")
        await #expect(throws: GitError.detachedHead) { try await repository.push() }
    }

    @Test func rejectedPushIsClassifiedAndPullRecovers() async throws {
        let (test, remote) = try await repositoryWithRemote()
        defer { test.remove() }
        let repository = try await test.repository
        try await repository.push()
        // Someone else pushes from another clone.
        let other = test.folder.deletingLastPathComponent().appending(path: "other", directoryHint: .isDirectory)
        try await test.git("clone", "--quiet", remote.path(percentEncoded: false), other.path(percentEncoded: false))
        try Data("theirs\n".utf8).write(to: other.appending(path: "theirs.txt"))
        try await test.git("add", ".", in: other)
        try await test.git("commit", "--quiet", "-m", "Theirs", in: other)
        try await test.git("push", "--quiet", in: other)
        try test.write("mine.txt", "mine\n")
        try await repository.commit(message: "Mine", files: try await repository.status().changes)
        try await test.git("config", "pull.rebase", "true")

        await #expect {
            try await repository.push()
        } throws: { error in
            (error as? GitError)?.failure == .pushRejected
        }

        try await repository.pull()
        try await repository.push()
        #expect(try await repository.status().branch.ahead == 0)
    }

    @Test func comparesABranchWithTheRemoteDefaultBranch() async throws {
        let (test, _) = try await repositoryWithRemote()
        defer { test.remove() }
        let repository = try await test.repository
        try await repository.push()
        try await test.git("checkout", "--quiet", "-b", "feature")
        try test.write("feature.txt", "new\n")
        try await repository.commit(message: "Add feature\n\nBecause.", files: try await repository.status().changes)

        let base = try await repository.comparisonBase(for: "main")
        let log = try await repository.commitLog(since: base)
        let diff = try await repository.branchDiff(since: base)

        #expect(base == "origin/main")
        #expect(log.contains("Add feature"))
        #expect(log.contains("Because."))
        #expect(!log.contains("Initial commit"))
        #expect(diff.contains("+new"))
        #expect(try await repository.comparisonBase(for: "missing") == "missing")
    }

    @Test func createsDetachedTaskWorktrees() async throws {
        let test = try await TestRepository.make()
        defer { test.remove() }
        let repository = try await test.repository
        let location = test.folder.deletingLastPathComponent().appending(path: "worktrees", directoryHint: .isDirectory)

        let worktree = try await repository.createWorktree(forTask: "PR 12", in: location, detached: true)

        #expect(worktree.isDetached)
        #expect(worktree.branch == nil)
        #expect(try await repository.branches(includingRemote: false).map(\.name) == ["main"])
    }

    /// Enough files for git to check them out in parallel (`Repository.parallelCheckout`), with an
    /// executable and a symlink among them: the worktree gets every one, unchanged.
    @Test func checksOutEveryFileOfALargeTreeInParallel() async throws {
        let test = try await TestRepository.make()
        defer { test.remove() }
        for index in 0..<300 {
            try test.write("src/module\(index % 10)/file\(index).txt", "contents \(index)\n")
        }
        try test.write("run.sh", "#!/bin/sh\necho hi\n")
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755], ofItemAtPath: test.folder.appending(path: "run.sh").path(percentEncoded: false))
        try FileManager.default.createSymbolicLink(
            atPath: test.folder.appending(path: "link.txt").path(percentEncoded: false),
            withDestinationPath: "README.md")
        try await test.git("add", "-A")
        try await test.git("commit", "--quiet", "-m", "Many files")
        let repository = try await test.repository
        let folder = test.folder.deletingLastPathComponent().appending(path: "big", directoryHint: .isDirectory)

        let worktree = try await repository.addWorktree(at: folder, newBranch: "task/big")

        let files = try await test.git("ls-files", in: worktree.path).split(separator: "\n")
        #expect(files.count == 303)
        #expect(try await test.git("status", "--porcelain", in: worktree.path).isEmpty)
        let file = try String(contentsOf: worktree.path.appending(path: "src/module7/file157.txt"), encoding: .utf8)
        #expect(file == "contents 157\n")
        let mode =
            try FileManager.default.attributesOfItem(
                atPath: worktree.path.appending(path: "run.sh").path(percentEncoded: false))[.posixPermissions] as? Int
        #expect(mode == 0o755)
        #expect(
            try FileManager.default.destinationOfSymbolicLink(
                atPath: worktree.path.appending(path: "link.txt").path(percentEncoded: false)) == "README.md")
    }

    /// A new task in a repository without commits can't get a worktree: there's no commit to
    /// branch from. `hasCommits` is what tells the app to offer the project folder instead.
    @Test func aRepositoryWithoutCommitsHasNothingToBranchFrom() async throws {
        let test = try await TestRepository.make(commit: false)
        defer { test.remove() }
        let repository = try await test.repository
        let folder = test.folder.deletingLastPathComponent().appending(path: "task", directoryHint: .isDirectory)

        #expect(try await repository.hasCommits() == false)
        await #expect(throws: GitError.self) {
            try await repository.addWorktree(at: folder, newBranch: "task/first")
        }

        try test.write("README.md", "# Test\n")
        try await test.git("add", "README.md")
        try await test.git("commit", "--quiet", "-m", "First")
        #expect(try await repository.hasCommits())
    }

    @Test func listsLocalAndRemoteBranches() async throws {
        let (test, _) = try await repositoryWithRemote()
        defer { test.remove() }
        let repository = try await test.repository
        try await repository.push()
        try await test.git("branch", "topic")

        let branches = try await repository.branches()

        #expect(branches.filter { !$0.isRemote }.map(\.name).sorted() == ["main", "topic"])
        #expect(branches.first { $0.isCurrent }?.name == "main")
        #expect(branches.first { $0.name == "main" }?.upstream == "origin/main")
        #expect(branches.filter(\.isRemote).map(\.name) == ["origin/main"])
        #expect(try await repository.branches(includingRemote: false).allSatisfy { !$0.isRemote })
    }

    @Test func createsListsAndRemovesTaskWorktrees() async throws {
        let test = try await TestRepository.make()
        defer { test.remove() }
        let repository = try await test.repository
        let location = test.folder.deletingLastPathComponent().appending(path: "worktrees", directoryHint: .isDirectory)

        let first = try await repository.createWorktree(
            forTask: "Fix the Login bug", branchPrefix: "native/", in: location)
        let second = try await repository.createWorktree(
            forTask: "Fix the login bug", branchPrefix: "native/", in: location)

        #expect(first.branch == "native/fix-the-login-bug")
        #expect(second.branch == "native/fix-the-login-bug-2")
        #expect(first.path.lastPathComponent == "fix-the-login-bug")
        #expect(first.path.deletingLastPathComponent().lastPathComponent == "repo")
        #expect(try await repository.worktrees().count == 3)

        // A worktree reports its own branch and knows it's linked.
        let linked = try #require(try await test.git.repository(at: first.path))
        #expect(linked.isLinkedWorktree)
        #expect(linked.name == "repo")
        #expect(try await linked.status().branch.name == "native/fix-the-login-bug")
        #expect(
            try await repository.branches(includingRemote: false).first { $0.name == "native/fix-the-login-bug" }?
                .worktreePath != nil)

        try await repository.removeWorktree(at: second.path)
        #expect(try await repository.worktrees().count == 2)
        #expect(!FileManager.default.fileExists(atPath: second.path.path(percentEncoded: false)))
    }

    @Test func removingADirtyWorktreeCheckpointsItsWork() async throws {
        let test = try await TestRepository.make()
        defer { test.remove() }
        let repository = try await test.repository
        let location = test.folder.deletingLastPathComponent().appending(path: "worktrees", directoryHint: .isDirectory)
        let worktree = try await repository.createWorktree(forTask: "Agent work", in: location)
        try Data("unsaved\n".utf8).write(to: worktree.path.appending(path: "draft.txt"))
        try Data("# Edited\n".utf8).write(to: worktree.path.appending(path: "README.md"))

        // Without force git refuses, and nothing is lost.
        await #expect(throws: GitError.self) {
            try await repository.removeWorktree(at: worktree.path, checkpoint: false)
        }

        let checkpoint = try #require(try await repository.removeWorktree(at: worktree.path, force: true))

        #expect(checkpoint.reference.hasPrefix("refs/native-checkpoints/agent-work-"))
        #expect(try await repository.checkpoints().map(\.reference) == [checkpoint.reference])
        #expect(try await test.git("show", "\(checkpoint.commit):draft.txt") == "unsaved\n")
        #expect(try await test.git("show", "\(checkpoint.commit):README.md") == "# Edited\n")
        // The checkpoint sits on top of the branch's commit.
        let parent = try await test.git("rev-parse", "\(checkpoint.commit)^")
        #expect(parent == (try await test.git("rev-parse", "agent-work")))
        // The main checkout's index and files are untouched.
        #expect(try await repository.status().isClean)

        // Restoring brings the worktree and its uncommitted work back.
        let restored = try await repository.restoreWorktree(at: worktree.path, branch: "agent-work", from: checkpoint)
        #expect(restored.branch == "agent-work")
        #expect(try String(contentsOf: worktree.path.appending(path: "draft.txt"), encoding: .utf8) == "unsaved\n")
        #expect(try String(contentsOf: worktree.path.appending(path: "README.md"), encoding: .utf8) == "# Edited\n")
    }

    @Test func removingAWorktreeWhoseFolderIsGonePrunesIt() async throws {
        let test = try await TestRepository.make()
        defer { test.remove() }
        let repository = try await test.repository
        let location = test.folder.deletingLastPathComponent().appending(path: "worktrees", directoryHint: .isDirectory)
        let worktree = try await repository.createWorktree(forTask: "Gone", in: location)
        try FileManager.default.removeItem(at: worktree.path)

        #expect(try await repository.removeWorktree(at: worktree.path) == nil)
        #expect(try await repository.worktrees().count == 1)
    }

    @Test func watcherReportsWorkingTreeAndGitStateChanges() async throws {
        let test = try await TestRepository.make()
        defer { test.remove() }
        let repository = try await test.repository
        let changes = FSEventsRepositoryMonitor(latency: 0.05).changes(in: repository)
        let received = Mutex<[RepositoryChange]>([])
        // One consumer for the whole test: cancelling an iteration would end the stream.
        let collector = Task {
            for await change in changes {
                received.withLock { $0.append(change) }
            }
        }
        defer { collector.cancel() }

        try test.write("watched.txt", "hello\n")
        #expect(await eventually { received.withLock { $0.contains { $0.paths.contains("watched.txt") } } })

        try await repository.stage(["watched.txt"])
        #expect(await eventually { received.withLock { $0.contains(where: \.gitStateChanged) } })
    }

    /// Polls `condition` for up to five seconds.
    private func eventually(_ condition: () -> Bool) async -> Bool {
        for _ in 0..<100 {
            if condition() { return true }
            try? await Task.sleep(for: .milliseconds(50))
        }
        return condition()
    }
}
