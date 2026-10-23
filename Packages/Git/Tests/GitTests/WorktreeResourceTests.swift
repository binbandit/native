import Foundation
import Testing

@testable import Git

@Suite("Worktree resource limits")
struct WorktreeResourceTests {
    enum Creation: CaseIterable {
        case newBranch, detached, existingBranch, restored
    }

    /// The hook observes the real checkout's configuration and scheduling, including the
    /// configuration inherited by child git processes. A user's all-core setting must not win.
    @Test(arguments: Creation.allCases)
    func checkoutLeavesCPUForOtherWork(_ creation: Creation) async throws {
        let test = try await TestRepository.make()
        defer { test.remove() }
        let normalPriority = try await test.git.runTool("sh", ["-c", "ps -o nice= -p $$"], in: test.folder)
        let defaultPriority = try #require(Int(normalPriority.text.trimmingCharacters(in: .whitespacesAndNewlines)))
        try await test.git("config", "checkout.workers", "0")
        let hook = ".git/hooks/post-checkout"
        try test.write(
            hook,
            """
            #!/bin/sh
            git config --get checkout.workers > checkout-workers
            ps -o nice= -p $$ > checkout-nice
            """)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755], ofItemAtPath: test.folder.appending(path: hook).path(percentEncoded: false))
        let repository = try await test.repository
        let location = test.folder.deletingLastPathComponent().appending(path: "worktrees")
        let worktree: Worktree
        switch creation {
        case .newBranch:
            worktree = try await repository.createWorktree(forTask: "Task", in: location)
        case .detached:
            worktree = try await repository.createWorktree(forTask: "Task", in: location, detached: true)
        case .existingBranch:
            try await test.git("branch", "task")
            worktree = try await repository.createWorktree(checkingOut: "task", folderName: "task", in: location)
        case .restored:
            try await test.git("branch", "task")
            worktree = try await repository.restoreWorktree(at: location, branch: "task", from: nil)
        }
        let workers = try String(contentsOf: worktree.path.appending(path: "checkout-workers"), encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let priority = try String(contentsOf: worktree.path.appending(path: "checkout-nice"), encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let workerCount = try #require(Int(workers))
        #expect(workerCount == 1)
        let checkoutPriority = try #require(Int(priority))
        #expect(checkoutPriority > defaultPriority || defaultPriority >= 19)
        #expect(try await test.git("config", "--local", "checkout.workers").trimmingCharacters(in: .newlines) == "0")
        #expect(
            try String(contentsOf: worktree.path.appending(path: "README.md"), encoding: .utf8)
                == test.read("README.md"))
    }

    @Test func checkoutKeepsTheConfiguredGitAndEnvironment() async throws {
        let test = try await TestRepository.make()
        defer { test.remove() }
        let executable = test.folder.appending(path: ".git/custom git")
        try test.write(
            ".git/custom git",
            """
            #!/bin/sh
            [ "$WORKTREE_FIXTURE" = yes ] || exit 70
            exec git "$@"
            """)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755], ofItemAtPath: executable.path(percentEncoded: false))
        var environment = TestRepository.environment
        environment["WORKTREE_FIXTURE"] = "yes"
        let git = Git(environment: environment, executable: executable.path(percentEncoded: false))
        let repository = try #require(try await git.repository(at: test.folder))
        let path = test.folder.deletingLastPathComponent().appending(path: "task with spaces")

        let worktree = try await repository.addWorktree(at: path, newBranch: "task/custom-git")

        #expect(worktree.branch == "task/custom-git")
        #expect(
            try String(contentsOf: worktree.path.appending(path: "README.md"), encoding: .utf8)
                == test.read("README.md"))
    }
}
