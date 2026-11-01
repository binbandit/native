import Foundation
import Testing

@testable import Git

@Suite struct DefaultBranchNameTests {
    @Test func localMainIsKnownWithoutARemote() async throws {
        let test = try await TestRepository.make()
        defer { test.remove() }
        #expect(try await test.repository.defaultBranchName() == "main")
        try await test.git("switch", "--quiet", "--create", "feature")
        #expect(try await test.repository.defaultBranchName() == "main")
    }

    @Test func remoteHeadWinsForACustomDefaultBranch() async throws {
        let test = try await TestRepository.make()
        defer { test.remove() }
        try await test.git("remote", "add", "origin", test.folder.path())
        try await test.git("update-ref", "refs/remotes/origin/trunk", "HEAD")
        try await test.git("symbolic-ref", "refs/remotes/origin/HEAD", "refs/remotes/origin/trunk")
        #expect(try await test.repository.defaultBranchName() == "trunk")
    }

    @Test func unknownDefaultStaysUnknown() async throws {
        let test = try await TestRepository.make()
        defer { test.remove() }
        try await test.git("branch", "--move", "trunk")
        #expect(try await test.repository.defaultBranchName() == nil)
    }
}
