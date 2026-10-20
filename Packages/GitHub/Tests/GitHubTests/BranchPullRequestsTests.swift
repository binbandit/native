import Exec
import Foundation
import Testing

@testable import GitHub

/// Which of a branch's pull requests a task's badge shows, from `gh pr list --head` output: the
/// captured list (#974, #972, #957, #952, newest first) with its states rewritten per case.
struct BranchPullRequestsTests {
    @Test func newestOpenWinsOverANewerClosedOne() throws {
        let found = try #require(
            BranchPullRequests(try pullRequests(states: [974: "CLOSED", 972: "OPEN", 957: "MERGED", 952: "CLOSED"])))

        #expect(found.current.number == 972)
        #expect(found.others.map(\.number) == [974, 957, 952])
        #expect(!found.othersAreEarlier)
    }

    @Test func withoutAnOpenOneTheNewestShows() throws {
        let found = try #require(
            BranchPullRequests(try pullRequests(states: [974: "MERGED", 972: "CLOSED", 957: "MERGED", 952: "CLOSED"])))

        #expect(found.current.number == 974)
        #expect(found.others.map(\.number) == [972, 957, 952])
        #expect(found.othersAreEarlier)
    }

    @Test func aBranchWithOnePullRequestHasNoOthers() throws {
        let only = try pullRequests(states: [:]).filter { $0.number == 957 }
        let found = try #require(BranchPullRequests(only))

        #expect(found.current.number == 957)
        #expect(found.others.isEmpty)
        #expect(found.othersAreEarlier)
        #expect(BranchPullRequests([]) == nil)
    }

    @Test func listsEveryStateForTheBranch() async throws {
        let runner = FakeRunner { _ in FakeRunner.success(try Fixtures.data("pr-list")) }
        let folder = URL(filePath: "/work/tree", directoryHint: .isDirectory)
        let found = try await GitHubCLI(environment: ["PATH": "/usr/bin"], runner: runner)
            .pullRequests(forBranch: "ai/tty-5-observer", in: .directory(folder))

        #expect(found?.current.number == 974)
        let arguments = try #require(runner.commands.first?.arguments)
        #expect(arguments.contains("--state=all"))
        #expect(arguments.contains("--head=ai/tty-5-observer"))
    }

    /// The captured list with each numbered pull request's state replaced.
    private func pullRequests(states: [Int: String]) throws -> [PullRequest] {
        guard var list = try JSONSerialization.jsonObject(with: Fixtures.data("pr-list")) as? [[String: Any]] else {
            throw CocoaError(.coderReadCorrupt)
        }
        for index in list.indices {
            if let number = list[index]["number"] as? Int, let state = states[number] {
                list[index]["state"] = state
            }
        }
        return try GitHubJSON.decode([PullRequest].self, from: JSONSerialization.data(withJSONObject: list))
    }
}
