import Foundation
import Testing

@testable import Git

@Suite struct BranchPatchTests {
    @Test func aBranchPatchAppliesOnAnotherCloneWithItsCommits() async throws {
        let test = try await TestRepository.make()
        defer { test.remove() }
        try await test.git("switch", "--quiet", "--create", "rounding-half-even")
        try test.write("Sources/Rounding.swift", "let mode = \"half-even\"\n")
        try await test.git("add", "Sources/Rounding.swift")
        try await test.git("commit", "--quiet", "-m", "Round half-even")
        try test.write("README.md", "# Test\n\nRounds half-even.\n")
        try await test.git("commit", "--quiet", "-am", "Document rounding")
        // Uncommitted work stays out of the patch.
        try test.write("Scratch.txt", "not yet\n")

        let patch = try #require(try await test.repository.branchPatch())
        #expect(patch.commits == 2)
        #expect(patch.base == "main")
        let text = String(decoding: patch.data, as: UTF8.self)
        #expect(text.contains("Subject: [PATCH 1/2] Round half-even"))
        #expect(!text.contains("Scratch.txt"))

        let clone = test.folder.deletingLastPathComponent().appending(path: "connected", directoryHint: .isDirectory)
        try await test.git("clone", "--quiet", "--branch", "main", test.folder.path(), clone.path())
        let file = test.folder.deletingLastPathComponent().appending(path: "rounding.patch")
        try patch.data.write(to: file)
        try await test.git("am", "--quiet", file.path(), in: clone)

        let subjects = try await test.git("log", "--format=%s", "-2", in: clone)
        #expect(subjects == "Document rounding\nRound half-even\n")
        let applied = try String(contentsOf: clone.appending(path: "Sources/Rounding.swift"), encoding: .utf8)
        #expect(applied == "let mode = \"half-even\"\n")
    }

    @Test func aBranchWithNoCommitsOfItsOwnGivesAnEmptyPatch() async throws {
        let test = try await TestRepository.make()
        defer { test.remove() }
        try await test.git("switch", "--quiet", "--create", "fresh")
        try test.write("README.md", "Uncommitted\n")

        let patch = try #require(try await test.repository.branchPatch())
        #expect(patch.commits == 0)
        #expect(patch.data.isEmpty)
    }

    @Test func theDefaultBranchWithNowhereToPushHasNoPatch() async throws {
        let test = try await TestRepository.make()
        defer { test.remove() }

        #expect(try await test.repository.branchPatch() == nil)
    }
}
