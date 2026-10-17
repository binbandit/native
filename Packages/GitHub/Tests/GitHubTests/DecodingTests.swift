import Foundation
import Testing
@testable import GitHub

struct DecodingTests {
    @Test func authStatusListsTheActiveAccountPerHost() throws {
        let status = try Fixtures.decode(AuthStatus.self, from: "auth-status-all-accounts")

        #expect(status.hosts["github.com"]?.map(\.login) == ["binbandit", "sage-smudge", "WastedHippie"])
        let active = try #require(status.activeAccounts.first)
        #expect(status.activeAccounts.count == 1)
        #expect(active.login == "binbandit")
        #expect(active.state == .success)
        #expect(active.tokenSource == "keyring")
    }

    @Test func signedOutAuthStatusHasNoHosts() throws {
        // What gh prints (exit 0) with no logins; the explanation goes to stderr.
        let status = try GitHubJSON.decode(AuthStatus.self, from: Data(#"{"hosts":{}}"#.utf8))
        #expect(status.activeAccounts.isEmpty)
    }

    @Test func currentUser() throws {
        let user = try Fixtures.decode(GitHubUser.self, from: "api-user")

        #expect(user.login == "binbandit")
        #expect(user.avatarURL?.host() == "avatars.githubusercontent.com")
        #expect(user.profileURL == URL(string: "https://github.com/binbandit"))
    }

    @Test func rateLimitBudgets() throws {
        let limit = try Fixtures.decode(RateLimit.self, from: "rate-limit")

        #expect(limit.search.limit == 30)
        #expect(limit.graphql.limit == 5000)
        #expect(limit.core.resetsAt > Date(timeIntervalSince1970: 1_700_000_000))
        #expect(limit.exhaustedUntil == nil)
    }

    @Test func repositoryForAFolder() throws {
        let repository = try Fixtures.decode(GitHubRepository.self, from: "repo-view")

        #expect(repository.nameWithOwner == "binbandit/oh-fx")
        #expect(repository.defaultBranch == "main")
        #expect(repository.description == nil)
        #expect(repository.viewerPermission == "ADMIN")
        #expect(!repository.isFork)
    }

    @Test func pullRequestDetail() throws {
        let pullRequest = try Fixtures.decode(PullRequest.self, from: "pr-view")

        #expect(pullRequest.number == 974)
        #expect(pullRequest.repository == "binbandit/oh-fx")
        #expect(pullRequest.state == .open)
        #expect(pullRequest.headRefName == "ai/gateway-10b-deferred-usage")
        #expect(pullRequest.baseRefName == "main")
        #expect(pullRequest.headRefOid == "ca006cb7eba250eab79ab653fe465321d76ce8ba")
        // gh prints "" for a repository without review requirements.
        #expect(pullRequest.reviewDecision == nil)
        #expect(pullRequest.mergeable == .mergeable)
        #expect(pullRequest.mergeStatus == .blocked)
        #expect(pullRequest.additions == 700)
        #expect(pullRequest.author == GitHubActor(login: "binbandit"))
        #expect(pullRequest.statusCheckRollup.allSatisfy { $0.kind == .checkRun })
        let checks = try #require(pullRequest.checks)
        #expect(checks.total == pullRequest.statusCheckRollup.count)
    }

    @Test func rollupMixesCheckRunsAndCommitStatuses() throws {
        let pullRequest = try Fixtures.decode(PullRequest.self, from: "pr-view-status-context")

        let status = try #require(pullRequest.statusCheckRollup.first { $0.kind == .statusContext })
        #expect(status.name == "CodeRabbit")
        #expect(status.outcome == .passed)
        // An empty target URL means none.
        #expect(status.detailsURL == nil)
        #expect(pullRequest.reviewDecision == .reviewRequired)
        #expect(pullRequest.latestReviews.first?.state == .approved)
        #expect(pullRequest.latestReviews.first?.author?.login == "coderabbitai")
    }

    @Test func pullRequestList() throws {
        let pullRequests = try Fixtures.decode([PullRequest].self, from: "pr-list")

        #expect(pullRequests.count == 4)
        #expect(pullRequests.allSatisfy { $0.state == .open && $0.repository == "binbandit/oh-fx" })
        #expect(pullRequests.contains { !$0.labels.isEmpty })
    }

    @Test func checksListedByGh() throws {
        let checks = try Fixtures.decode([PullRequestCheck].self, from: "pr-checks")

        let failing = try #require(checks.first { $0.bucket == .fail })
        #expect(failing.outcome == .failed)
        #expect(failing.link?.host() == "github.com")
        let neutral = try #require(checks.first { $0.state == "NEUTRAL" })
        #expect(neutral.bucket == .skipping)
        #expect(neutral.outcome == .skipped)
        #expect(neutral.workflow == nil)
        let summary = try #require(CheckSummary(outcomes: checks.map(\.outcome)))
        #expect(summary.state == .failing)
    }

    @Test func searchResults() throws {
        let results = try Fixtures.decode([PullRequestSearchResult].self, from: "search-authored")

        let first = try #require(results.first)
        #expect(first.id.hasPrefix("PR_"))
        #expect(first.repository == "binbandit/oh-fx")
        // Search prints states in lowercase.
        #expect(results.allSatisfy { $0.state == .open })
    }

    @Test func searchRecognizesApps() throws {
        let results = try Fixtures.decode([PullRequestSearchResult].self, from: "search-review-requested")

        let dependabot = try #require(results.first { $0.author?.login == "dependabot[bot]" })
        #expect(dependabot.author?.isBot == true)
        #expect(dependabot.labels.map(\.name).contains("dependencies"))
        #expect(results.first { $0.author?.login == "sage-smudge" }?.author?.isBot == false)
    }

    @Test func statusesFillInWhatSearchLacks() throws {
        let response = try Fixtures.decode(PullRequestStatus.Response.self, from: "graphql-pull-request-status")
        let statuses = response.data.nodes.compactMap { $0?.status }

        let status = try #require(statuses.first { $0.id == "PR_kwDOU2D-Vc8AAAABH6WVsA" })
        #expect(status.headRefName == "ai/tty-5-observer")
        #expect(status.mergeable == .mergeable)
        #expect(status.reviewDecision == nil)
        let checks = try #require(status.checks)
        #expect(checks.state == .failing)
        #expect(checks.failed == 1)
        #expect(checks.passed == 9)
        #expect(checks.skipped == 1)
        #expect(statuses.contains { $0.reviewDecision == .reviewRequired })
    }

    @Test func unresolvedStatusNodesAreSkipped() throws {
        let json = #"{"data":{"nodes":[null,{},{"id":"PR_1","headRefName":"a","baseRefName":"main","reviewDecision":"SOMETHING_NEW","mergeable":"UNKNOWN","additions":1,"deletions":0,"commits":{"nodes":[{"commit":{"statusCheckRollup":null}}]}}]}}"#
        let response = try GitHubJSON.decode(PullRequestStatus.Response.self, from: Data(json.utf8))
        let statuses = response.data.nodes.compactMap { $0?.status }

        #expect(statuses.map(\.id) == ["PR_1"])
        #expect(statuses.first?.reviewDecision == .other)
        #expect(statuses.first?.checks == nil)
    }

    @Test func summaryFromSearchAndStatus() throws {
        let results = try Fixtures.decode([PullRequestSearchResult].self, from: "search-authored")
        let response = try Fixtures.decode(PullRequestStatus.Response.self, from: "graphql-pull-request-status")
        let statuses = Dictionary(uniqueKeysWithValues: response.data.nodes.compactMap { $0?.status }.map { ($0.id, $0) })
        let result = try #require(results.first)

        let summary = PullRequestSummary(result, status: statuses[result.id])
        #expect(summary.reference == "binbandit/oh-fx#972")
        #expect(summary.headRefName == "ai/tty-5-observer")
        #expect(summary.checks?.state == .failing)
        #expect(summary.additions == 1583)
    }
}
