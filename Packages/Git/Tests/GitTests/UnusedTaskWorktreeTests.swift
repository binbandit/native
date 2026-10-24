import Foundation
import Testing

@testable import Git

@Suite("Unused task worktree cleanup")
struct UnusedTaskWorktreeTests {
    @Test func receiptSurvivesReopeningAndIsAbsentForUserWorktrees() async throws {
        let test = try await TestRepository.make()
        defer { test.remove() }
        let repository = try await test.repository
        let folder = test.folder.deletingLastPathComponent().appending(path: "task with spaces")
        let worktree = try await repository.addWorktree(at: folder, newBranch: "task")
        #expect(try await repository.unusedTaskWorktree(at: folder) == nil)
        try await repository.recordUnusedTaskWorktree(worktree)
        let reopened = try await test.repository
        let receipt = try #require(await reopened.unusedTaskWorktree(at: folder))
        #expect(receipt.branch == "task")
        #expect(try await reopened.removeUnusedTaskWorktree(receipt))
        #expect(try await reopened.unusedTaskWorktree(at: folder) == nil)
    }

    @Test func removesUntouchedCheckoutAndKeepsBranch() async throws {
        let test = try await TestRepository.make()
        defer { test.remove() }
        let repository = try await test.repository
        let folder = test.folder.deletingLastPathComponent().appending(path: "task")
        let worktree = try await repository.addWorktree(at: folder, newBranch: "task")
        let receipt = try #require(UnusedTaskWorktree(worktree: worktree))
        #expect(try await repository.removeUnusedTaskWorktree(receipt))
        #expect(!FileManager.default.fileExists(atPath: folder.path))
        #expect(try await repository.hasBranch("task"))
        #expect(try test.read("README.md").contains("Hello"))
    }

    @Test(arguments: [
        "tracked", "staged", "untracked", "ignored", "commit", "branch", "locked", "assume-unchanged", "skip-worktree",
    ])
    func preservesChangedCheckout(change: String) async throws {
        let test = try await TestRepository.make()
        defer { test.remove() }
        let repository = try await test.repository
        let folder = test.folder.deletingLastPathComponent().appending(path: "task")
        let worktree = try await repository.addWorktree(at: folder, newBranch: "task")
        let receipt = try #require(UnusedTaskWorktree(worktree: worktree))
        switch change {
        case "assume-unchanged", "skip-worktree":
            try await test.git("update-index", "--\(change)", "README.md", in: folder)
            try Data("Keep hidden edits\n".utf8).write(to: folder.appending(path: "README.md"))
        case "tracked", "staged", "commit":
            try Data("Keep this edit\n".utf8).write(to: folder.appending(path: "README.md"))
            if change != "tracked" { try await test.git("add", "README.md", in: folder) }
            if change == "commit" { try await test.git("commit", "-m", "Work", in: folder) }
        case "untracked":
            try Data("Keep this file\n".utf8).write(to: folder.appending(path: "notes.txt"))
        case "ignored":
            try test.write(".git/info/exclude", "notes.txt\n")
            try Data("Keep ignored work\n".utf8).write(to: folder.appending(path: "notes.txt"))
        case "branch":
            try await test.git("switch", "-c", "different", in: folder)
        case "locked":
            try await test.git("worktree", "lock", folder.path)
        default: break
        }
        #expect(try await !repository.removeUnusedTaskWorktree(receipt))
        #expect(FileManager.default.fileExists(atPath: folder.path))
    }

    @Test func neverGrantsReceiptForProjectFolder() async throws {
        let test = try await TestRepository.make()
        defer { test.remove() }
        let main = try #require(await test.repository.worktrees().first(where: \.isMain))
        #expect(UnusedTaskWorktree(worktree: main) == nil)
    }
}
