import Foundation
import Testing

@testable import Git

/// Checking out a branch that lives elsewhere, the way a pull request from a fork is: local bare
/// repositories stand in for the base repository and the fork, so nothing touches the network.
@Suite("Remotes, fetching and tracking")
struct RemoteTests {
    /// A clone of a base repository whose `refs/pull/7/head` (as GitHub keeps it) and a fork's
    /// `feat/x` both point at one commit past `main`.
    private struct PullRequestSetup {
        let test: TestRepository
        let fork: URL
        let head: String

        static func make() async throws -> PullRequestSetup {
            let test = try await TestRepository.make()
            let scratch = test.folder.deletingLastPathComponent()
            let base = scratch.appending(path: "base.git", directoryHint: .isDirectory)
            let fork = scratch.appending(path: "fork.git", directoryHint: .isDirectory)
            try await test.git("init", "--quiet", "--bare", "--initial-branch=main", base.path(percentEncoded: false))
            try await test.git("remote", "add", "origin", base.path(percentEncoded: false))
            try await test.git("push", "--quiet", "origin", "main")
            try await test.git("clone", "--quiet", "--bare", base.path(percentEncoded: false), fork.path(percentEncoded: false))

            // The contributor's commit, pushed to their fork and mirrored as the pull ref.
            try await test.git("switch", "--quiet", "--create", "contributor")
            try test.write("feature.txt", "feature\n")
            try await test.git("add", "feature.txt")
            try await test.git("commit", "--quiet", "-m", "Feature")
            let head = try await test.git("rev-parse", "HEAD").trimmingCharacters(in: .whitespacesAndNewlines)
            try await test.git("push", "--quiet", fork.path(percentEncoded: false), "HEAD:refs/heads/feat/x")
            try await test.git("push", "--quiet", base.path(percentEncoded: false), "HEAD:refs/pull/7/head")
            try await test.git("switch", "--quiet", "main")
            try await test.git("branch", "--quiet", "--delete", "--force", "contributor")
            return PullRequestSetup(test: test, fork: fork, head: head)
        }
    }

    @Test func listsRemotesWithTheirFetchURLs() async throws {
        let setup = try await PullRequestSetup.make()
        defer { setup.test.remove() }
        let repository = try await setup.test.repository
        try await repository.addRemote("contributor", url: setup.fork.path(percentEncoded: false))

        let remotes = try await repository.remoteURLs()

        #expect(remotes.map(\.name) == ["contributor", "origin"])
        #expect(remotes.first?.url == setup.fork.path(percentEncoded: false))
        try await repository.removeRemote("contributor")
        #expect(try await repository.remoteURLs().map(\.name) == ["origin"])
    }

    @Test func aPullRefChecksOutInItsOwnWorktreeWithANote() async throws {
        let setup = try await PullRequestSetup.make()
        defer { setup.test.remove() }
        let repository = try await setup.test.repository
        let location = setup.test.folder.deletingLastPathComponent().appending(path: "worktrees", directoryHint: .isDirectory)
        // A folder already where the worktree would go is skipped, not overwritten.
        let taken = location.appending(path: "repo/pr-7-fix-v2", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: taken, withIntermediateDirectories: true)
        try Data("someone's\n".utf8).write(to: taken.appending(path: "file.txt"))

        try await repository.fetch(from: "origin", refspecs: ["refs/pull/7/head:refs/heads/pr-7-fix.v2"])
        let worktree = try await repository.createWorktree(
            checkingOut: "pr-7-fix.v2", folderName: "pr-7-fix.v2", in: location)
        try await repository.setNote("nativePullRequest", "https://github.com/o/r/pull/7", on: "pr-7-fix.v2")

        #expect(worktree.path.lastPathComponent == "pr-7-fix-v2-2")
        #expect(worktree.branch == "pr-7-fix.v2")
        #expect(worktree.head == setup.head)
        #expect(try await repository.notes("nativePullRequest") == ["pr-7-fix.v2": "https://github.com/o/r/pull/7"])
        #expect(try await repository.notes("nativepullrequest").count == 1)
        #expect(try await repository.notes("somethingElse").isEmpty)
    }

    @Test func aTrackedForkBranchPushesBackUnderItsOwnName() async throws {
        let setup = try await PullRequestSetup.make()
        defer { setup.test.remove() }
        let repository = try await setup.test.repository
        let location = setup.test.folder.deletingLastPathComponent().appending(path: "worktrees", directoryHint: .isDirectory)
        try await repository.addRemote("contributor", url: setup.fork.path(percentEncoded: false))
        try await repository.fetch(
            from: "contributor", refspecs: ["+refs/heads/feat/x:refs/remotes/contributor/feat/x"])
        try await repository.createBranch("pr-7-feature", at: "refs/remotes/contributor/feat/x")
        try await repository.setUpstream(of: "pr-7-feature", remote: "contributor", remoteBranch: "feat/x")
        let worktree = try await repository.createWorktree(checkingOut: "pr-7-feature", folderName: "pr-7-feature", in: location)
        let checkout = try #require(try await setup.test.git.repository(at: worktree.path))
        #expect(try await checkout.status().branch.upstream == "contributor/feat/x")

        try Data("fix\n".utf8).write(to: worktree.path.appending(path: "fix.txt"))
        try await checkout.commit(message: "Fix", files: try await checkout.status().changes)
        try await checkout.push()

        let tip = try await setup.test.git("rev-parse", "HEAD", in: worktree.path)
        let pushed = try await setup.test.git("rev-parse", "refs/heads/feat/x", in: setup.fork)
        #expect(pushed == tip)
        // Nothing new appeared under the local name.
        let branches = try await setup.test.git("branch", "--list", "--format=%(refname:short)", in: setup.fork)
        #expect(branches.split(separator: "\n") == ["feat/x", "main"])
        #expect(try await checkout.status().branch.ahead == 0)
    }

    @Test func aMovedHeadIsSeenAndFastForwarded() async throws {
        let setup = try await PullRequestSetup.make()
        defer { setup.test.remove() }
        let repository = try await setup.test.repository
        let location = setup.test.folder.deletingLastPathComponent().appending(path: "worktrees", directoryHint: .isDirectory)
        try await repository.fetch(from: "origin", refspecs: ["refs/pull/7/head:refs/heads/pr-7"])
        let worktree = try await repository.createWorktree(checkingOut: "pr-7", folderName: "pr-7", in: location)
        let checkout = try #require(try await setup.test.git.repository(at: worktree.path))
        #expect(try await checkout.contains(setup.head))

        // The contributor pushes again; the pull ref follows.
        let other = setup.test.folder.deletingLastPathComponent().appending(path: "contributor", directoryHint: .isDirectory)
        try await setup.test.git("clone", "--quiet", "--branch", "feat/x", setup.fork.path(percentEncoded: false), other.path(percentEncoded: false))
        try Data("more\n".utf8).write(to: other.appending(path: "more.txt"))
        try await setup.test.git("add", ".", in: other)
        try await setup.test.git("commit", "--quiet", "-m", "More", in: other)
        let moved = try await setup.test.git("rev-parse", "HEAD", in: other).trimmingCharacters(in: .whitespacesAndNewlines)
        let base = try #require(try await repository.remoteURLs().first?.url)
        try await setup.test.git("push", "--quiet", base, "HEAD:refs/pull/7/head", in: other)

        #expect(try await checkout.hasCommit(moved) == false)
        try await checkout.fetch(from: "origin", refspecs: ["refs/pull/7/head"])
        #expect(try await checkout.hasCommit(moved))
        #expect(try await checkout.contains(moved) == false)

        // Uncommitted changes to a file the update brings stop it, changing nothing.
        try Data("mine\n".utf8).write(to: worktree.path.appending(path: "more.txt"))
        await #expect {
            try await checkout.fastForward(to: moved)
        } throws: { error in
            (error as? GitError)?.failure == .localChangesWouldBeOverwritten
        }
        try FileManager.default.removeItem(at: worktree.path.appending(path: "more.txt"))

        try await checkout.fastForward(to: moved)
        #expect(try await checkout.contains(moved))
    }
}
