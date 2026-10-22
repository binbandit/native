import Foundation
import Testing

@testable import GitHub

/// Mutating commands are only ever exercised here, as argument lists.
struct CommandTests {
    let folder = URL(filePath: "/tmp/checkout", directoryHint: .isDirectory)

    @Test func readsAreReadOnly() {
        let reads: [GitHubCommand] = [
            .version, .authStatus(), .currentUser, .rateLimit, .repository(.directory(folder)),
            .search(PullRequestSearch(.author)), .pullRequestStatuses(ids: ["PR_1"]),
            .listPullRequests(PullRequestListFilter(), in: .directory(folder)),
            .viewPullRequest(.number(1), in: .directory(folder)), .checks(.number(1), in: .directory(folder)),
        ]
        #expect(reads.allSatisfy { !$0.isMutating })
    }

    @Test func authStatusAsksForEveryAccount() {
        #expect(GitHubCommand.authStatus().arguments == ["auth", "status", "--json", "hosts"])
        #expect(GitHubCommand.authStatus(host: "ghe.example.com").arguments.last == "--hostname=ghe.example.com")
    }

    @Test func searchesEachInvolvement() {
        let authored = GitHubCommand.search(PullRequestSearch(.author, limit: 25))
        #expect(
            authored.arguments == [
                "search", "prs", "--author=@me", "--state=open", "--archived=false", "--sort=updated", "--order=desc",
                "--limit=25", "--json",
                "id,number,title,url,state,isDraft,repository,author,assignees,labels,commentsCount,createdAt,updatedAt",
            ])
        #expect(GitHubCommand.search(PullRequestSearch(.reviewRequested)).arguments[2] == "--review-requested=@me")
        #expect(
            GitHubCommand.search(PullRequestSearch(.assignee, user: "octocat")).arguments[2] == "--assignee=octocat")
    }

    @Test func searchKeywordsFollowADoubleDash() {
        let search = GitHubCommand.search(PullRequestSearch(.author, repositories: ["a/b"], keywords: " -label:wip "))
        #expect(Array(search.arguments.suffix(3)) == ["--repo=a/b", "--", "-label:wip"])
    }

    @Test func statusesGoThroughStdin() throws {
        let command = GitHubCommand.pullRequestStatuses(ids: ["PR_1", "PR_2"])
        #expect(command.arguments == ["api", "graphql", "--input", "-"])

        struct Body: Decodable {
            struct Variables: Decodable { var ids: [String] }
            var query: String
            var variables: Variables
        }
        let body = try JSONDecoder().decode(Body.self, from: try #require(command.input))
        #expect(body.variables.ids == ["PR_1", "PR_2"])
        #expect(body.query.contains("nodes(ids: $ids)"))
    }

    @Test func locationIsAFolderOrARepoFlag() {
        let local = GitHubCommand.viewPullRequest(.number(7), in: .directory(folder))
        #expect(local.directory == folder)
        #expect(!local.arguments.contains { $0.hasPrefix("--repo") })

        let remote = GitHubCommand.checks(.url(URL(filePath: "/a/b/pull/7")), in: .remote("a/b"))
        #expect(remote.directory == nil)
        #expect(
            remote.arguments == ["pr", "checks", "file:///a/b/pull/7", "--json", PullRequestCheck.fields, "--repo=a/b"])

        // `repo view` names the repository as its argument.
        #expect(GitHubCommand.repository(.remote("a/b")).arguments.prefix(3) == ["repo", "view", "a/b"])
    }

    @Test func listFiltersByBranch() {
        let command = GitHubCommand.listPullRequests(
            PullRequestListFilter(state: .all, head: "feature/x", limit: 10), in: .directory(folder))
        #expect(command.arguments.prefix(5) == ["pr", "list", "--state=all", "--limit=10", "--head=feature/x"])
    }

    @Test func createPassesTheHeadAndPipesTheBody() throws {
        let command = GitHubCommand.createPullRequest(
            NewPullRequest(
                title: "-Fix: the thing", body: "Line one\n--body is not a flag", head: "fix/thing", base: "main",
                isDraft: true),
            in: folder
        )
        #expect(command.isMutating)
        #expect(command.directory == folder)
        #expect(
            command.arguments == [
                "pr", "create", "--title=-Fix: the thing", "--body-file=-", "--head=fix/thing", "--base=main",
                "--draft",
            ])
        #expect(String(decoding: try #require(command.input), as: UTF8.self) == "Line one\n--body is not a flag")
    }

    @Test func createWithoutBaseUsesTheDefaultBranch() {
        let command = GitHubCommand.createPullRequest(NewPullRequest(title: "T", body: "", head: "h"), in: folder)
        #expect(command.arguments == ["pr", "create", "--title=T", "--body-file=-", "--head=h"])
    }

    @Test func checkoutRunsInTheGivenWorktree() {
        let command = GitHubCommand.checkout(.number(42), in: folder, localBranch: "pr-42")
        #expect(command.isMutating)
        #expect(command.directory == folder)
        #expect(command.arguments == ["pr", "checkout", "42", "--branch=pr-42"])
        #expect(
            GitHubCommand.checkout(.number(42), in: folder, detach: true).arguments == [
                "pr", "checkout", "42", "--detach",
            ])
    }

    @Test func closeReopenAndCommentNameTheRepository() {
        let close = GitHubCommand.close(.number(7), in: .remote("a/b"))
        #expect(close.arguments == ["pr", "close", "7", "--repo=a/b"])
        #expect(close.isMutating)
        #expect(GitHubCommand.reopen(.number(7), in: .remote("a/b")).arguments == ["pr", "reopen", "7", "--repo=a/b"])
        let comment = GitHubCommand.comment("-- looks good", on: .number(7), in: .remote("a/b"))
        // The body goes through stdin, so one starting with "-" can't be read as a flag.
        #expect(comment.arguments == ["pr", "comment", "7", "--body-file=-", "--repo=a/b"])
        #expect(comment.input == Data("-- looks good".utf8))
        #expect(comment.isMutating)
    }

    @Test func mergeIsExplicitAboutMethodAndHead() {
        let command = GitHubCommand.merge(
            .number(9), in: .remote("a/b"), method: .squash, deleteBranch: true, matchHeadCommit: "abc123")
        #expect(command.isMutating)
        #expect(
            command.arguments == [
                "pr", "merge", "9", "--squash", "--delete-branch", "--match-head-commit=abc123", "--repo=a/b",
            ])
    }

    @Test func openInBrowser() {
        #expect(
            GitHubCommand.openInBrowser(.branch("x"), in: .directory(folder)).arguments == ["pr", "view", "x", "--web"])
    }
}
