import Exec
import Foundation
import Testing

@testable import GitHub

/// Looking up local branches' merged pull requests, for Clean Up Merged.
struct MergedPullRequestTests {
    let environment = ["PATH": "/usr/bin:/bin", "HOME": "/Users/someone"]
    let directory = URL(filePath: "/Users/someone/cli", directoryHint: .isDirectory)

    @Test func asksOnceForEveryBranchByHeadAndLink() async throws {
        let runner = FakeRunner { command in
            switch command.arguments.first {
            case "repo": FakeRunner.success(Data(#"{"name":"cli","nameWithOwner":"cli/cli","url":"https://github.com/cli/cli"}"#.utf8))
            case "api": FakeRunner.success(try Fixtures.data("graphql-merged-pull-requests"))
            default: FakeRunner.failure(1, "unexpected")
            }
        }
        let found = try await GitHubCLI(environment: environment, runner: runner).mergedPullRequests(
            for: [
                MergedPullRequest.Query(
                    branch: "release-help", head: "bdehamer-release-create-atomicity-help",
                    pullRequest: URL(string: "https://github.com/cli/cli/pull/14722")),
                MergedPullRequest.Query(
                    branch: "still-open", head: "no-such-branch-for-native-tests",
                    pullRequest: URL(string: "https://github.com/cli/cli/pull/14727")),
            ], in: directory)

        // The same pull request found both ways counts once; an open one doesn't count.
        #expect(found.keys.sorted() == ["release-help"])
        let merged = try #require(found["release-help"]?.first)
        #expect(found["release-help"]?.count == 1)
        #expect(merged.number == 14722)
        #expect(merged.headRefOid == "9e1e1c929f882fd93e1c67ea520a4529352aab9a")
        #expect(merged.baseRefName == "trunk")
        #expect(merged.mergedAt != nil)

        #expect(runner.commands.map { $0.arguments.prefix(2) } == [["repo", "view"], ["api", "graphql"]])
        #expect(runner.commands.allSatisfy { $0.directory == directory.path(percentEncoded: false) })
    }

    @Test func branchNamesAreVariablesNotQueryText() throws {
        let command = GitHubCommand.mergedPullRequests(
            [MergedPullRequest.Query(branch: "x", head: #"evil") { viewer { login } } #"#)],
            owner: "o", name: "r", in: directory)
        let body = try #require(command.input)
        let request = try #require(try JSONSerialization.jsonObject(with: body) as? [String: Any])
        let query = try #require(request["query"] as? String)
        let variables = try #require(request["variables"] as? [String: String])

        #expect(!query.contains("evil"))
        #expect(query.contains("h0: pullRequests(headRefName: $h0, states: MERGED"))
        #expect(!query.contains("resource("))
        #expect(variables == ["owner": "o", "name": "r", "h0": #"evil") { viewer { login } } #"#])
    }

    @Test func noBranchesAsksNothing() async throws {
        let runner = FakeRunner { _ in FakeRunner.failure(1, "unexpected") }
        let found = try await GitHubCLI(environment: environment, runner: runner).mergedPullRequests(
            for: [], in: directory)
        #expect(found.isEmpty)
        #expect(runner.commands.isEmpty)
    }
}
