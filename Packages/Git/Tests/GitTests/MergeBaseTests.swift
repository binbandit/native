import Foundation
import Testing

@testable import Git

@Suite("Where two tasks' worktrees started")
struct MergeBaseTests {
    /// Two agents given one brief work in two worktrees from the same commit. Comparing what each
    /// changed starts at that commit, whether they committed their work or not.
    @Test func findsTheSharedStartOfTwoWorktrees() async throws {
        let test = try await TestRepository.make()
        defer { test.remove() }
        let repository = try await test.repository
        let start = try #require(try await repository.headCommit())
        let root = test.folder.deletingLastPathComponent()
        let first = try await repository.addWorktree(at: root.appending(path: "first"), newBranch: "task/first")
        let second = try await repository.addWorktree(at: root.appending(path: "second"), newBranch: "task/second")
        try await test.git("commit", "--quiet", "--allow-empty", "-m", "Committed", in: first.path)
        let firstRepository = try #require(try await test.git.repository(at: first.path))
        let secondRepository = try #require(try await test.git.repository(at: second.path))
        try Data("Uncommitted\n".utf8).write(to: second.path.appending(path: "notes.txt"))

        let firstHead = try #require(try await firstRepository.headCommit())
        let secondHead = try #require(try await secondRepository.headCommit())
        #expect(try await firstRepository.mergeBase(firstHead, secondHead) == start)

        let changes = try await secondRepository.treeChanges(
            from: start, to: try await secondRepository.snapshot().tree)
        #expect(changes.map(\.path) == ["notes.txt"])
    }

    @Test func unrelatedHistoriesHaveNoBase() async throws {
        let test = try await TestRepository.make()
        defer { test.remove() }
        let repository = try await test.repository
        let head = try #require(try await repository.headCommit())
        try await test.git("checkout", "--quiet", "--orphan", "other")
        try await test.git("commit", "--quiet", "--allow-empty", "-m", "Unrelated")
        let other = try #require(try await repository.headCommit())

        #expect(try await repository.mergeBase(head, other) == nil)
    }
}
