import Foundation
import Testing

@testable import Git

/// What a force-push would drop, read from what the last fetch left, against a local bare remote.
@Suite("What a push would drop")
struct PushReachTests {
    @Test func listsTheRemoteCommitsTheBranchDoesNotHave() async throws {
        let test = try await TestRepository.make()
        defer { test.remove() }
        let remote = test.folder.deletingLastPathComponent().appending(path: "origin.git", directoryHint: .isDirectory)
        try await test.git("init", "--quiet", "--bare", "--initial-branch=main", remote.path(percentEncoded: false))
        try await test.git("remote", "add", "origin", remote.path(percentEncoded: false))
        for subject in ["First on the remote", "Second on the remote"] {
            try test.write("notes.txt", subject)
            try await test.git("add", "notes.txt")
            try await test.git("commit", "--quiet", "-m", subject)
        }
        try await test.git("push", "--quiet", "--set-upstream", "origin", "main")
        try await test.git("reset", "--quiet", "--hard", "HEAD~2")
        let repository = try await test.repository

        let dropped = try #require(
            try await repository.commits(on: "main", of: "origin", missingFrom: "main", limit: 1))
        #expect(dropped.total == 2)
        #expect(dropped.newest.map(\.subject) == ["Second on the remote"])
        let unfetched = try await repository.commits(on: "never-fetched", of: "origin", missingFrom: "main", limit: 3)
        #expect(unfetched?.total == nil)
    }

    @Test func usesPushURLsInsteadOfFetchURLs() async throws {
        let test = try await TestRepository.make()
        defer { test.remove() }
        try await test.git("remote", "add", "origin", "https://example.invalid/fetch/repo.git")
        try await test.git("config", "remote.origin.pushurl", "ssh://git@push.example.invalid/write/repo.git")
        let repository = try await test.repository
        #expect(try await repository.pushURLs(for: "origin") == ["ssh://git@push.example.invalid/write/repo.git"])
        try await test.git("config", "--add", "remote.origin.pushurl", "https://mirror.example.invalid/repo.git")
        #expect(try await repository.pushURLs(for: "origin").count == 2)
    }

    @Test func headPushNamesTheLocalFeatureBranchInsteadOfTheRemoteDefault() async throws {
        let test = try await TestRepository.make()
        defer { test.remove() }
        try await test.git("remote", "add", "origin", "https://example.invalid/repo.git")
        try await test.git("update-ref", "refs/remotes/origin/main", "HEAD")
        try await test.git("symbolic-ref", "refs/remotes/origin/HEAD", "refs/remotes/origin/main")
        try await test.git("switch", "--quiet", "-c", "feature")
        let repository = try await test.repository
        let branch = try #require(try await repository.pushBranch(for: "HEAD", to: "origin"))
        #expect(branch == "feature")
        #expect(try await repository.commits(on: branch, of: "origin", missingFrom: "HEAD", limit: 3) == nil)
        #expect(try await repository.pushBranch(for: "main", to: "origin") == "main")
    }

    @Test func configuredSourceOnlyDestinationsStayUnknown() async throws {
        let test = try await TestRepository.make()
        defer { test.remove() }
        try await test.git("remote", "add", "origin", "https://example.invalid/repo.git")
        try await test.git("config", "remote.origin.push", "refs/heads/main:refs/heads/release")
        let repository = try await test.repository
        #expect(try await repository.pushBranch(for: "main", to: "origin") == nil)
        #expect(try await repository.pushBranch(for: "HEAD", to: "origin") == nil)
    }

    @Test func upstreamModeCanOverrideASourceOnlyDestination() async throws {
        let test = try await TestRepository.make()
        defer { test.remove() }
        try await test.git("remote", "add", "origin", "https://example.invalid/repo.git")
        try await test.git("config", "push.default", "upstream")
        try await test.git("config", "branch.main.remote", "origin")
        try await test.git("config", "branch.main.merge", "refs/heads/release")
        let repository = try await test.repository
        #expect(try await repository.pushBranch(for: "main", to: "origin") == nil)
        #expect(try await repository.pushBranch(for: "HEAD", to: "origin") == nil)
    }
}
