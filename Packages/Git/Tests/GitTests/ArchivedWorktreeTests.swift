import Exec
import Foundation
import Testing

@testable import Git

/// Archived task worktrees come back from what git keeps, not from anything in memory, so unarchiving
/// works after Native relaunches, and after it quits partway through archiving or restoring.
@Suite("Archived worktrees")
struct ArchivedWorktreeTests {
    @Test func comesBackAfterARelaunchWithItsBranchAndUncommittedWork() async throws {
        let scenario = try await Scenario.make()
        defer { scenario.test.remove() }
        try scenario.write("draft.txt", "unsaved\n")
        try await scenario.archive(deletingBranch: true)
        #expect(try await scenario.test.git("branch", "--list", "task").isEmpty)

        // A fresh Git stands in for Native relaunching: only the repository knows what was archived.
        let relaunched = Git(
            environment: TestRepository.environment, runner: LocalCommandRunner(), monitor: FSEventsRepositoryMonitor())
        let main = try #require(try await relaunched.repository(at: scenario.test.folder))
        let archived = try #require(try await main.archivedWorktrees().first)
        #expect(archived.branch == "task")
        #expect(archived.checkpoint != nil)

        let restored = try await main.restoreArchivedWorktree(archived)

        #expect(restored.branch == "task")
        #expect(try scenario.read("draft.txt") == "unsaved\n")
        #expect(try await main.archivedWorktrees().isEmpty)
        #expect(try await main.hasArchivedBranch("task") == false)
    }

    @Test func aWorktreeNativeQuitBeforeRemovingKeepsItsWork() async throws {
        let scenario = try await Scenario.make()
        defer { scenario.test.remove() }
        try scenario.write("draft.txt", "unsaved\n")
        let main = try await scenario.test.repository
        let worktree = try await scenario.worktree
        let checkpoint = try await worktree.checkpoint(named: "task")
        try await main.recordArchivedWorktree(
            ArchivedWorktree(path: scenario.path, branch: "task", checkpoint: checkpoint))
        try scenario.write("draft.txt", "edited since\n")

        try await main.restoreArchivedWorktree(try #require(try await main.archivedWorktrees().first))

        #expect(try scenario.read("draft.txt") == "edited since\n")
        #expect(try await main.archivedWorktrees().isEmpty)
    }

    @Test func aRestoreNativeQuitPartwayThroughFinishes() async throws {
        let scenario = try await Scenario.make()
        defer { scenario.test.remove() }
        try scenario.write("draft.txt", "unsaved\n")
        try await scenario.archive(deletingBranch: true)
        let main = try await scenario.test.repository
        let archived = try #require(try await main.archivedWorktrees().first)
        // Quit after the branch and folder came back, before the uncommitted work did.
        try await main.restoreArchivedBranch("task")
        try await main.restoreWorktree(at: scenario.path, branch: "task", from: nil)

        try await main.restoreArchivedWorktree(archived)

        #expect(try scenario.read("draft.txt") == "unsaved\n")
        #expect(try await main.archivedWorktrees().isEmpty)
    }

    @Test func recordsFolderNamesWithDotsAndSpaces() async throws {
        let scenario = try await Scenario.make(folder: "my task.v2 copy")
        defer { scenario.test.remove() }
        try await scenario.archive(deletingBranch: false)
        let archived = try #require(try await scenario.test.repository.archivedWorktrees().first)

        #expect(archived.path.lastPathComponent == "my task.v2 copy")
        #expect(archived.branch == "task")
        #expect(archived.checkpoint == nil)
    }
}

/// A repository with a task worktree on branch `task`, archived the way Native's GitStore does it.
private struct Scenario {
    let test: TestRepository
    let path: URL

    static func make(folder: String = "abc12") async throws -> Scenario {
        let test = try await TestRepository.make()
        let path = test.folder.deletingLastPathComponent().appending(
            path: "worktrees/\(folder)", directoryHint: .isDirectory)
        try await test.git("worktree", "add", "--quiet", "-b", "task", path.path(percentEncoded: false))
        return Scenario(test: test, path: path)
    }

    var worktree: Repository {
        get async throws { try #require(await test.git.repository(at: path)) }
    }

    func write(_ name: String, _ contents: String) throws {
        try Data(contents.utf8).write(to: path.appending(path: name))
    }

    func read(_ name: String) throws -> String {
        try String(contentsOf: path.appending(path: name), encoding: .utf8)
    }

    /// Checkpoint, record, remove, then (optionally) delete the branch, keeping a copy.
    func archive(deletingBranch: Bool) async throws {
        let main = try await test.repository
        let checkpoint = try await worktree.checkpoint(named: path.lastPathComponent)
        try await main.recordArchivedWorktree(ArchivedWorktree(path: path, branch: "task", checkpoint: checkpoint))
        try await main.removeWorktree(at: path, force: true, checkpoint: false)
        if deletingBranch {
            try await main.archiveBranch("task")
        }
    }
}
