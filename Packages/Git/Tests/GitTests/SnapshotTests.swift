import Foundation
import Testing

@testable import Git

@Suite("Working tree snapshots and what changed since one")
struct SnapshotTests {
    @Test func comparesCommittedAndUncommittedWorkAlike() async throws {
        let test = try await TestRepository.make()
        defer { test.remove() }
        try test.write("old.txt", "keep\n")
        try test.write("gone.txt", "bye\n")
        try await test.git("add", ".")
        try await test.git("commit", "--quiet", "-m", "Files")
        // Uncommitted work from before the snapshot isn't part of what changes after it.
        try test.write("before.txt", "already here\n")
        let repository = try await test.repository
        let start = try await repository.snapshot()

        try test.write("README.md", "# Test\n\nHello.\nOne more line.\n")
        try await test.git("commit", "--quiet", "-am", "Committed in the turn")
        try test.write("new.txt", "a\nb\n")
        try await test.git("mv", "old.txt", "renamed.txt")
        try FileManager.default.removeItem(at: test.folder.appending(path: "gone.txt"))
        let now = try await repository.snapshot()

        let changes = try await repository.treeChanges(from: start.tree, to: now.tree)
        #expect(changes.map(\.path) == ["gone.txt", "new.txt", "README.md", "renamed.txt"])
        #expect(changes.map(\.kind) == [.deleted, .added, .modified, .renamed])
        #expect(changes.first { $0.path == "README.md" }?.stats == LineStats(additions: 1))
        #expect(changes.first { $0.path == "new.txt" }?.stats == LineStats(additions: 2))
        #expect(changes.first { $0.path == "renamed.txt" }?.originalPath == "old.txt")
        #expect(start.head != now.head)
    }

    @Test func leavesTheIndexRefsAndStatusAlone() async throws {
        let test = try await TestRepository.make()
        defer { test.remove() }
        try test.write("staged.txt", "staged\n")
        try await test.git("add", "staged.txt")
        try test.write("untracked.txt", "loose\n")
        try test.write(".gitignore", "ignored.txt\n")
        try test.write("ignored.txt", "build output\n")
        let repository = try await test.repository
        let status = try await test.git("status", "--porcelain=v2", "--untracked-files=all")
        let refs = try await test.git("for-each-ref")
        let gitFiles = try FileManager.default.contentsOfDirectory(atPath: repository.gitDirectory.path())

        // What a snapshot would store beyond the tracked changes: not the ignored file.
        #expect(try await repository.untrackedFileCount() == 2)

        let snapshot = try await repository.snapshot()

        #expect(try await test.git("status", "--porcelain=v2", "--untracked-files=all") == status)
        #expect(try await test.git("for-each-ref") == refs)
        #expect(
            try FileManager.default.contentsOfDirectory(atPath: repository.gitDirectory.path()).sorted()
                == gitFiles.sorted())
        let files = try await test.git("ls-tree", "-r", "--name-only", snapshot.tree)
        #expect(files.split(separator: "\n") == [".gitignore", "README.md", "staged.txt", "untracked.txt"])
        #expect(try await repository.hasObject(snapshot.tree))
        #expect(try await !repository.hasObject(String(repeating: "0", count: 40)))
    }

    @Test func undoneWorkComparesEqual() async throws {
        let test = try await TestRepository.make()
        defer { test.remove() }
        let repository = try await test.repository
        let start = try await repository.snapshot()
        try test.write("README.md", "Rewritten\n")
        try test.write("README.md", "# Test\n\nHello.\n")

        let now = try await repository.snapshot()

        #expect(try await repository.treeChanges(from: start.tree, to: now.tree).isEmpty)
    }

    @Test func readsBothSidesOfAChange() async throws {
        let test = try await TestRepository.make()
        defer { test.remove() }
        let repository = try await test.repository
        let start = try await repository.snapshot()
        try test.write("README.md", "# Test\n\nHello again.\n")
        try test.write("new.txt", "fresh\n")
        let now = try await repository.snapshot()
        let changes = try await repository.treeChanges(from: start.tree, to: now.tree)

        let edited = try await repository.versions(of: try #require(changes.last), from: start.tree, to: now.tree)
        let added = try await repository.versions(of: try #require(changes.first), from: start.tree, to: now.tree)

        #expect(edited.oldText == "# Test\n\nHello.\n")
        #expect(edited.newText == "# Test\n\nHello again.\n")
        #expect(added.old == nil)
        #expect(added.newText == "fresh\n")
    }

    @Test func findsWhereHeadWasAtATime() async throws {
        let test = try await TestRepository.make()
        defer { test.remove() }
        let repository = try await test.repository
        let first = try #require(try await test.git("rev-parse", "HEAD").split(separator: "\n").first)
        try await Task.sleep(for: .seconds(1.1))
        let between = Date.now
        try await Task.sleep(for: .seconds(1.1))
        try test.write("README.md", "Later\n")
        try await test.git("commit", "--quiet", "-am", "Later")

        #expect(try await repository.head(at: between) == String(first))
        #expect(try await repository.head(at: .now) != String(first))
    }

    @Test func branchBaseIsWhereTheBranchLeftTheDefaultBranch() async throws {
        let test = try await TestRepository.make()
        defer { test.remove() }
        let repository = try await test.repository
        let main = try #require(try await repository.resolve("HEAD"))
        // The default branch with nowhere to push: nothing of its own to compare.
        #expect(try await repository.branchBase() == nil)

        try await test.git("switch", "--quiet", "--create", "feature")
        try test.write("README.md", "Feature\n")
        try await test.git("commit", "--quiet", "-am", "Feature")

        #expect(try await repository.branchBase() == BranchBase(commit: main, name: "main"))
    }

    @Test func onTheDefaultBranchTheBaseIsItsUpstream() async throws {
        let test = try await TestRepository.make()
        defer { test.remove() }
        let origin = test.folder.deletingLastPathComponent().appending(path: "origin.git")
        try await test.git("init", "--quiet", "--bare", origin.path(percentEncoded: false))
        try await test.git("remote", "add", "origin", origin.path(percentEncoded: false))
        try await test.git("push", "--quiet", "--set-upstream", "origin", "main")
        let pushed = try #require(try await test.repository.resolve("HEAD"))
        try test.write("README.md", "Unpushed\n")
        try await test.git("commit", "--quiet", "-am", "Unpushed")

        #expect(try await test.repository.branchBase() == BranchBase(commit: pushed, name: "origin/main"))
    }
}
