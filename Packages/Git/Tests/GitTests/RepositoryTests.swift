import Foundation
import Testing

@testable import Git

@Suite("Repository against real temporary repositories")
struct RepositoryTests {
    @Test func detectsRepositoriesFromSubfolders() async throws {
        let test = try await TestRepository.make()
        defer { test.remove() }
        try test.write("Sources/Deep/File.swift", "let x = 1\n")

        let repository = try #require(try await test.git.repository(at: test.folder.appending(path: "Sources/Deep")))
        #expect(repository.root.resolvingSymlinksInPath() == test.folder.resolvingSymlinksInPath())
        #expect(repository.name == "repo")
        #expect(!repository.isLinkedWorktree)

        let plain = try TestRepository(name: "plain")
        defer { plain.remove() }
        #expect(try await plain.git.repository(at: plain.folder) == nil)
    }

    @Test func statusCoversEveryArea() async throws {
        let test = try await TestRepository.make()
        defer { test.remove() }
        try test.write("keep.txt", "one\ntwo\nthree\n")
        try test.write("old name.txt", "rename me\n")
        try await test.git("add", ".")
        try await test.git("commit", "--quiet", "-m", "Add files")

        try test.write("keep.txt", "one\n2\nthree\nfour\n")
        try await test.git("mv", "old name.txt", "new näme.txt")
        try test.write("staged.txt", "a\nb\n")
        try await test.git("add", "staged.txt")
        try test.write("staged.txt", "a\nb\nc\n")
        try test.write("dir with space/untracked ✓.txt", "x\ny")
        try FileManager.default.removeItem(at: test.folder.appending(path: "README.md"))

        let status = try await test.repository.status()

        #expect(status.branch.head == .branch("main"))
        #expect(status.branch.upstream == nil)
        #expect(status.staged.map(\.path) == ["new näme.txt", "staged.txt"])
        #expect(status.staged.first?.kind == .renamed)
        #expect(status.staged.first?.originalPath == "old name.txt")
        #expect(status.staged.last?.stats == LineStats(additions: 2))
        #expect(status.unstaged.map(\.path) == ["keep.txt", "README.md", "staged.txt"])
        #expect(status.unstaged.map(\.kind) == [.modified, .deleted, .modified])
        #expect(status.unstaged.first?.stats == LineStats(additions: 2, deletions: 1))
        #expect(status.untracked.map(\.path) == ["dir with space/untracked ✓.txt"])
        #expect(status.untracked.first?.stats == LineStats(additions: 2))
        // keep +2 -1, README -3, staged +3, untracked +2; the rename adds nothing.
        #expect(status.totals == LineStats(additions: 7, deletions: 4))
        #expect(status.changedFileCount == 5)
    }

    @Test func statusBeforeTheFirstCommit() async throws {
        let test = try await TestRepository.make(commit: false)
        defer { test.remove() }
        try test.write("a.txt", "1\n2\n")
        try await test.git("add", "a.txt")
        try test.write("b.txt", "1\n")

        let repository = try await test.repository
        let status = try await repository.status()

        #expect(status.branch.isUnborn)
        #expect(status.branch.name == "main")
        #expect(
            status.staged == [FileChange(path: "a.txt", kind: .added, area: .staged, stats: LineStats(additions: 2))])
        #expect(status.untracked.map(\.path) == ["b.txt"])
        #expect(status.totals == LineStats(additions: 3))

        try await repository.unstage(["a.txt"])
        #expect(try await repository.status().staged.isEmpty)
    }

    @Test func versionsOfEachArea() async throws {
        let test = try await TestRepository.make()
        defer { test.remove() }
        let repository = try await test.repository
        try test.write("README.md", "# Staged\n")
        try await repository.stage(["README.md"])
        try test.write("README.md", "# Working\n")
        try test.write("new.txt", "fresh\n")

        let status = try await repository.status()
        let staged = try await repository.versions(of: try #require(status.staged.first))
        let unstaged = try await repository.versions(of: try #require(status.unstaged.first))
        let untracked = try await repository.versions(of: try #require(status.untracked.first))

        #expect(staged.oldText == "# Test\n\nHello.\n")
        #expect(staged.newText == "# Staged\n")
        #expect(unstaged.oldText == "# Staged\n")
        #expect(unstaged.newText == "# Working\n")
        #expect(untracked.old == nil)
        #expect(untracked.newText == "fresh\n")
        #expect(!untracked.isBinary)
        #expect(try await repository.contents(of: "missing.txt", at: .head) == nil)
    }

    @Test func stagesUnstagesAndCommitsOddPaths() async throws {
        let test = try await TestRepository.make()
        defer { test.remove() }
        let repository = try await test.repository
        // Pathspec magic characters must be taken literally.
        let odd = "weird [name] *.txt"
        try test.write(odd, "x\n")
        try test.write("other.txt", "y\n")

        try await repository.stage([odd])
        var status = try await repository.status()
        #expect(status.staged.map(\.path) == [odd])
        #expect(status.untracked.map(\.path) == ["other.txt"])

        try await repository.unstage([odd])
        status = try await repository.status()
        #expect(status.staged.isEmpty)

        let commit = try await repository.commit(
            message: "Add odd file\n\nWith a body.", files: [try #require(status.untracked.first { $0.path == odd })])
        #expect(commit.count >= 40)
        status = try await repository.status()
        #expect(status.untracked.map(\.path) == ["other.txt"])
        #expect(
            try await test.git("log", "-1", "--format=%B").trimmingCharacters(in: .whitespacesAndNewlines)
                == "Add odd file\n\nWith a body.")
        #expect(try await repository.recentCommitSubjects() == ["Add odd file", "Initial commit"])
    }

    @Test func commitWithFilesUnstagesEverythingElse() async throws {
        let test = try await TestRepository.make()
        defer { test.remove() }
        let repository = try await test.repository
        try test.write("a.txt", "a\n")
        try test.write("b.txt", "b\n")
        try await repository.stage(["a.txt", "b.txt"])

        let status = try await repository.status()
        try await repository.commit(message: "Only b", files: status.staged.filter { $0.path == "b.txt" })

        let after = try await repository.status()
        #expect(after.untracked.map(\.path) == ["a.txt"])
        #expect(after.staged.isEmpty)
        #expect(
            try await test.git("show", "--name-only", "--format=", "HEAD").trimmingCharacters(
                in: .whitespacesAndNewlines) == "b.txt")
    }

    @Test func commitFailuresCarryGitsMessage() async throws {
        let test = try await TestRepository.make()
        defer { test.remove() }
        let repository = try await test.repository

        await #expect {
            try await repository.commit(message: "Nothing")
        } throws: { error in
            guard case .failed(_, _, let message) = error as? GitError else { return false }
            return message.contains("nothing to commit")
        }
    }

    @Test func discardsEachKindOfChange() async throws {
        let test = try await TestRepository.make()
        defer { test.remove() }
        let repository = try await test.repository
        try test.write("tracked.txt", "original\n")
        try await test.git("add", ".")
        try await test.git("commit", "--quiet", "-m", "Track")

        try test.write("tracked.txt", "edited\n")
        try test.write("added.txt", "new\n")
        try await repository.stage(["added.txt"])
        try test.write("scratch.txt", "junk\n")
        try test.write("README.md", "# Staged edit\n")
        try await repository.stage(["README.md"])

        let status = try await repository.status()
        let checkpoint = try #require(try await repository.discard(status.changes))

        #expect(try await repository.status().isClean)
        #expect(try test.read("tracked.txt") == "original\n")
        #expect(try test.read("README.md") == "# Test\n\nHello.\n")
        #expect(!test.exists("added.txt"))
        #expect(!test.exists("scratch.txt"))

        // The checkpoint brings all of it back, staged state included.
        try await repository.restore(checkpoint, paths: status.changes.map(\.path))
        let restored = try await repository.status()
        #expect(try test.read("tracked.txt") == "edited\n")
        #expect(try test.read("scratch.txt") == "junk\n")
        #expect(try test.read("README.md") == "# Staged edit\n")
        #expect(restored.staged.map(\.path) == ["added.txt", "README.md"])
        #expect(restored.unstaged.map(\.path) == ["tracked.txt"])
        #expect(restored.untracked.map(\.path) == ["scratch.txt"])
    }

    @Test func restoringADiscardedDeletionDeletesAgain() async throws {
        let test = try await TestRepository.make()
        defer { test.remove() }
        let repository = try await test.repository
        try FileManager.default.removeItem(at: test.folder.appending(path: "README.md"))

        let checkpoint = try #require(try await repository.discard(try await repository.status().changes))
        #expect(test.exists("README.md"))

        try await repository.restore(checkpoint, paths: ["README.md"])
        #expect(!test.exists("README.md"))
        #expect(try await repository.status().unstaged.map(\.kind) == [.deleted])
    }

    @Test func initializesARepository() async throws {
        let plain = try TestRepository(name: "fresh")
        defer { plain.remove() }

        let repository = try await plain.git.initializeRepository(at: plain.folder)

        #expect(try await repository.status().branch.isUnborn)
    }

    @Test func discardingUnstagedKeepsWhatsStaged() async throws {
        let test = try await TestRepository.make()
        defer { test.remove() }
        let repository = try await test.repository
        try test.write("README.md", "# Staged\n")
        try await repository.stage(["README.md"])
        try test.write("README.md", "# Unstaged on top\n")

        try await repository.discard(try await repository.status().unstaged)

        #expect(try test.read("README.md") == "# Staged\n")
        #expect(try await repository.status().staged.map(\.path) == ["README.md"])
    }

    @Test func patchIncludesTrackedAndUntrackedChanges() async throws {
        let test = try await TestRepository.make()
        defer { test.remove() }
        let repository = try await test.repository
        try test.write("README.md", "# Test\n\nGoodbye.\n")
        try test.write("new.swift", "print(1)\n")

        let patch = try await repository.patch(for: try await repository.status().changes)

        #expect(patch.contains("-Hello."))
        #expect(patch.contains("+Goodbye."))
        #expect(patch.contains("+++ b/new.swift"))
        #expect(patch.contains("+print(1)"))
    }

    @Test func ignoredPathsHonorGitignore() async throws {
        let test = try await TestRepository.make()
        defer { test.remove() }
        try test.write(".gitignore", "build/\n*.log\n")

        let ignored = try await test.repository.ignoredPaths(among: ["build/out.o", "debug.log", "Sources/App.swift"])

        #expect(ignored == ["build/out.o", "debug.log"])
    }
}
