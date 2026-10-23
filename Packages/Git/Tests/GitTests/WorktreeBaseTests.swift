import Exec
import Foundation
import Synchronization
import Testing

@testable import Git

@Suite("Task worktree bases")
struct WorktreeBaseTests {
    @Test func startsFromLatestRemoteWithoutChangingLocalCheckout() async throws {
        let test = try await TestRepository.make()
        defer { test.remove() }
        let remote = test.folder.deletingLastPathComponent().appending(path: "remote.git")
        try await test.git("init", "--bare", "--quiet", remote.path())
        try await test.git("remote", "add", "origin", remote.path())
        try await test.git("push", "--quiet", "--set-upstream", "origin", "main")
        let local = try await test.git("rev-parse", "HEAD").trimmingCharacters(in: .whitespacesAndNewlines)
        try test.write("remote.txt", "new remote content")
        try await test.git("add", "remote.txt")
        try await test.git("commit", "--quiet", "-m", "Remote update")
        let latest = try await test.git("rev-parse", "HEAD").trimmingCharacters(in: .whitespacesAndNewlines)
        try await test.git("push", "--quiet", "origin", "main")
        try await test.git("reset", "--hard", local)
        try test.write("README.md", "local uncommitted work")
        let repository = try await test.repository
        let folder = test.folder.deletingLastPathComponent().appending(path: "task")
        let base = try await repository.taskWorktreeBase(fetchRemote: true)
        let worktree = try await repository.addWorktree(at: folder, newBranch: "task", startPoint: base.commit)
        #expect(base.source == .remote)
        #expect(worktree.head == latest)
        #expect(try await test.git("rev-parse", "HEAD").trimmingCharacters(in: .whitespacesAndNewlines) == local)
        #expect(try test.read("README.md") == "local uncommitted work")
    }
    @Test(arguments: [true, false])
    func unavailableRemoteFallsBackAndPolicySkipsFetch(_ enabled: Bool) async throws {
        let runner = RunnerTests.RecordingRunner()
        let test = try await TestRepository.make(runner: runner)
        defer { test.remove() }
        try await test.git("remote", "add", "origin", test.folder.appending(path: "missing.git").path())
        try await test.git("config", "branch.main.remote", "origin")
        try await test.git("config", "branch.main.merge", "refs/heads/main")
        let repository = try await test.repository
        let local = try await test.git("rev-parse", "HEAD").trimmingCharacters(in: .whitespacesAndNewlines)
        runner.commands.withLock { $0.removeAll() }
        let base = try await repository.taskWorktreeBase(fetchRemote: enabled)
        #expect(base.commit == local)
        #expect(base.source == .local(enabled ? .fetchFailed : .disabled))
        let fetches = runner.commands.withLock { $0.filter { $0.arguments.contains("fetch") } }
        #expect(fetches.count == (enabled ? 1 : 0))
        if enabled {
            #expect(fetches.first?.executable == "nice")
            #expect(fetches.first?.arguments.prefix(2) == ["-n", "10"])
            #expect(fetches.first?.timeout == .seconds(15))
            #expect(fetches.first?.environment["GIT_TERMINAL_PROMPT"] == "0")
        }
        let worktree = try await repository.addWorktree(
            at: test.folder.deletingLastPathComponent().appending(path: "task"), newBranch: "task",
            startPoint: base.commit)
        #expect(worktree.head == local)
        #expect(try await test.git("for-each-ref", "refs/native/worktree-bases").isEmpty)
    }

    @Test(arguments: [false, true])
    func respectsUpstreamRemoteAndBranch(_ hasUpstream: Bool) async throws {
        let test = try await TestRepository.make()
        defer { test.remove() }
        let remote = test.folder.deletingLastPathComponent().appending(path: "remote.git")
        let remoteName = hasUpstream ? "team" : "origin"
        let remoteBranch = hasUpstream ? "release/stable" : "main"
        try await test.git("init", "--bare", "--quiet", remote.path())
        try await test.git("remote", "add", remoteName, remote.path())
        let local = try await test.git("rev-parse", "HEAD").trimmingCharacters(in: .whitespacesAndNewlines)
        try test.write("latest.txt", "latest")
        try await test.git("add", "latest.txt")
        try await test.git("commit", "--quiet", "-m", "Remote")
        let latest = try await test.git("rev-parse", "HEAD").trimmingCharacters(in: .whitespacesAndNewlines)
        try await test.git("push", "--quiet", remoteName, "HEAD:refs/heads/\(remoteBranch)")
        try await test.git("reset", "--hard", local)
        if hasUpstream {
            try await test.git("remote", "add", "origin", test.folder.appending(path: "wrong.git").path())
            try await test.git("config", "branch.main.remote", remoteName)
            try await test.git("config", "branch.main.merge", "refs/heads/\(remoteBranch)")
        }
        let base = try await test.repository.taskWorktreeBase(fetchRemote: true)
        #expect(base.commit == latest)
        #expect(base.source == .remote)
        #expect(try await test.git("for-each-ref", "refs/native/worktree-bases").isEmpty)
    }

    @Test func localAndDetachedCheckoutsNeedNoRemote() async throws {
        let test = try await TestRepository.make()
        defer { test.remove() }
        let repository = try await test.repository
        #expect(try await repository.taskWorktreeBase(fetchRemote: true).source == .local(.noRemote))
        try await test.git("switch", "--quiet", "--detach")
        #expect(try await repository.taskWorktreeBase(fetchRemote: true).source == .local(.detached))
    }

}
