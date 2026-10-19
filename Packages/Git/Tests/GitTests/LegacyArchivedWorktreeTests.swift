import Foundation
import Testing

@testable import Git

/// Task worktrees archived before Native recorded them: only the checkpoint and the branch (or its
/// copy) are left, and unarchiving works the record out from those.
@Suite("Worktrees archived before records")
struct LegacyArchivedWorktreeTests {
    @Test func aBranchRenamedAfterItsTitleIsFoundFromItsReflog() async throws {
        let legacy = try await LegacyArchive.make(folder: "ab3c4", renamedTo: "me/fix-login")
        defer { legacy.test.remove() }
        // Also at the same commit, but nothing ties it to the folder.
        try await legacy.test.git("branch", "me/other")
        let archivedAt = Date.now.addingTimeInterval(-1)
        try await legacy.archive()
        let main = try await legacy.test.repository

        let rebuilt = try await main.rebuildArchivedWorktree(at: legacy.path, title: nil, archivedAt: archivedAt)

        guard case .found(let archived) = rebuilt else { Issue.record("Expected a branch, got \(rebuilt)"); return }
        #expect(archived.branch == "me/fix-login")
        #expect(archived.checkpoint != nil)
        try await main.restoreArchivedWorktree(archived)
        #expect(try legacy.read("draft.txt") == "unsaved\n")
    }

    @Test func aDeletedBranchIsFoundByTheTasksTitle() async throws {
        let legacy = try await LegacyArchive.make(folder: "k3m9p", renamedTo: "me/tidy-docs")
        defer { legacy.test.remove() }
        try await legacy.commit("docs.md")
        try await legacy.archive(deletingBranch: true)
        let main = try await legacy.test.repository

        let rebuilt = try await main.rebuildArchivedWorktree(at: legacy.path, title: "Tidy docs", archivedAt: nil)

        guard case .found(let archived) = rebuilt else { Issue.record("Expected a branch, got \(rebuilt)"); return }
        #expect(archived.branch == "me/tidy-docs")
        try await main.restoreArchivedWorktree(archived)
        #expect(try legacy.read("draft.txt") == "unsaved\n")
        #expect(try legacy.read("docs.md") == "docs.md\n")
    }

    @Test func twoBranchesWithTheSameEvidenceAreAmbiguous() async throws {
        let legacy = try await LegacyArchive.make(folder: "q1w2e", renamedTo: "a/ok")
        defer { legacy.test.remove() }
        try await legacy.test.git("branch", "b/ok")
        // Deleting it drops the reflog that tied it to the folder; only the title is left.
        try await legacy.archive(deletingBranch: true)

        let rebuilt = try await legacy.test.repository.rebuildArchivedWorktree(
            at: legacy.path, title: "OK", archivedAt: nil)

        guard case .ambiguous(let names, let checkpoint) = rebuilt else { Issue.record("Got \(rebuilt)"); return }
        #expect(names == ["a/ok", "b/ok"])
        // Its uncommitted work is still saved, which the user hears.
        #expect(checkpoint != nil)
    }

    @Test func aBranchDeletedForGoodLeavesNothingToRestoreOn() async throws {
        let legacy = try await LegacyArchive.make(folder: "z9x8c", renamedTo: nil)
        defer { legacy.test.remove() }
        try await legacy.archive()
        try await legacy.test.git("branch", "-D", "me/z9x8c")

        let rebuilt = try await legacy.test.repository.rebuildArchivedWorktree(
            at: legacy.path, title: "Gone", archivedAt: nil)

        guard case .noBranch(let checkpoint) = rebuilt else { Issue.record("Got \(rebuilt)"); return }
        #expect(checkpoint != nil)
    }

    @Test func aCheckpointFromBeforeLaterCommitsIsntItsWork() async throws {
        let legacy = try await LegacyArchive.make(folder: "p0o9i", renamedTo: nil)
        defer { legacy.test.remove() }
        try await legacy.archive()
        // Unarchived, the draft dropped and a commit made, then archived again with nothing uncommitted.
        let main = try await legacy.test.repository
        try await main.restoreWorktree(at: legacy.path, branch: "me/p0o9i", from: nil)
        try await legacy.commit("later.md")
        // Committer dates are whole seconds; a real archive comes well after the first one's checkpoint.
        let archivedAt = Date.now.addingTimeInterval(1)
        try await legacy.archive()

        let rebuilt = try await main.rebuildArchivedWorktree(at: legacy.path, title: nil, archivedAt: archivedAt)

        #expect(rebuilt == .found(ArchivedWorktree(path: legacy.path, branch: "me/p0o9i", checkpoint: nil)))
    }

    @Test func aTaskArchivedAgainAfterItsWorktreeWasLostGetsItsWorkBack() async throws {
        let legacy = try await LegacyArchive.make(folder: "u7y6t", renamedTo: nil)
        defer { legacy.test.remove() }
        try await legacy.archive()
        let main = try await legacy.test.repository

        // An older Native unarchived it without its worktree; archiving it again removed nothing.
        let rebuilt = try await main.rebuildArchivedWorktree(
            at: legacy.path, title: nil, archivedAt: .now.addingTimeInterval(60))

        guard case .found(let archived) = rebuilt else { Issue.record("Expected a branch, got \(rebuilt)"); return }
        #expect(archived.checkpoint != nil)
        try await main.restoreArchivedWorktree(archived)
        #expect(try legacy.read("draft.txt") == "unsaved\n")
    }
}

/// A task worktree as an older Native made one: in a folder named after the provisional branch's
/// code, with uncommitted work, then archived without a record.
private struct LegacyArchive {
    let test: TestRepository
    let path: URL

    static func make(folder: String, renamedTo name: String?) async throws -> LegacyArchive {
        let test = try await TestRepository.make()
        let requested = test.folder.deletingLastPathComponent().appending(
            path: "worktrees/repo/\(folder)", directoryHint: .isDirectory)
        try await test.git("worktree", "add", "--quiet", "-b", "me/\(folder)", requested.path(percentEncoded: false))
        // As git spells it (`/private/var/…`), which its checkpoint names; the app compares spellings.
        let toplevel = try await test.git("rev-parse", "--show-toplevel", in: requested)
        let path = URL(filePath: toplevel.trimmingCharacters(in: .whitespacesAndNewlines), directoryHint: .isDirectory)
        if let name {
            try await test.git("branch", "--move", "me/\(folder)", name)
        }
        let legacy = LegacyArchive(test: test, path: path)
        try Data("unsaved\n".utf8).write(to: path.appending(path: "draft.txt"))
        return legacy
    }

    func read(_ name: String) throws -> String {
        try String(contentsOf: path.appending(path: name), encoding: .utf8)
    }

    func commit(_ name: String) async throws {
        try Data("\(name)\n".utf8).write(to: path.appending(path: name))
        try await test.git("add", name, in: path)
        try await test.git("commit", "--quiet", "-m", "Add \(name)", in: path)
    }

    /// What archiving did before records: checkpoint and remove, and maybe delete the branch.
    func archive(deletingBranch: Bool = false) async throws {
        let main = try await test.repository
        let branch = try #require(try await test.git.repository(at: path)?.status().branch.name)
        try await main.removeWorktree(at: path, force: true)
        if deletingBranch {
            try await main.archiveBranch(branch)
        }
    }
}
