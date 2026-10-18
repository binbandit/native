import Exec
import Foundation
import Testing

@testable import GitHub

/// Review writes, only ever as request bodies and against a scripted runner.
struct ReviewCommandTests {
    struct Body: Decodable {
        var query: String
        var variables: [String: Variable]
    }

    /// Any JSON value, to read variables back.
    indirect enum Variable: Decodable, Equatable {
        case string(String)
        case int(Int)
        case bool(Bool)
        case array([Variable])
        case object([String: Variable])
        case null

        init(from decoder: any Decoder) throws {
            let container = try decoder.singleValueContainer()
            if container.decodeNil() {
                self = .null
            } else if let value = try? container.decode(Int.self) {
                self = .int(value)
            } else if let value = try? container.decode(Bool.self) {
                self = .bool(value)
            } else if let value = try? container.decode(String.self) {
                self = .string(value)
            } else if let value = try? container.decode([Variable].self) {
                self = .array(value)
            } else {
                self = .object(try container.decode([String: Variable].self))
            }
        }
    }

    func body(_ command: GitHubCommand) throws -> Body {
        #expect(command.arguments == ["api", "graphql", "--input", "-"])
        return try JSONDecoder().decode(Body.self, from: try #require(command.input))
    }

    func input(_ command: GitHubCommand) throws -> [String: Variable] {
        guard case .object(let input) = try body(command).variables["input"] else {
            Issue.record("No input object")
            return [:]
        }
        return input
    }

    @Test func readsAreReadOnly() throws {
        let reference = PullRequestReference(owner: "a", name: "b", number: 7)
        for command in [
            GitHubCommand.pullRequestPage(reference), .timelinePage(reference, after: "c"),
            .changedFilesPage(reference, after: "c"),
        ] {
            #expect(!command.isMutating)
            #expect(try body(command).variables["number"] == .int(7))
        }
        let patches = GitHubCommand.filePatches(reference, page: 2)
        #expect(patches.arguments == ["api", "repos/a/b/pulls/7/files?per_page=100&page=2"])
        #expect(!patches.isMutating)
    }

    @Test func rangeCommentCarriesBothEnds() throws {
        let anchor = ReviewAnchor(path: "src/a.go", side: .right, line: 14, startLine: 10)
        let command = GitHubCommand.addReviewThread(
            reviewID: "PRR_1", anchor: anchor, body: "Use a constant.\n```suggestion\nx\n```")
        #expect(command.isMutating)
        #expect(try body(command).query.contains("addPullRequestReviewThread(input: $input)"))
        let input = try input(command)
        #expect(input["pullRequestReviewId"] == .string("PRR_1"))
        #expect(input["path"] == .string("src/a.go"))
        #expect(input["line"] == .int(14))
        #expect(input["side"] == .string("RIGHT"))
        #expect(input["startLine"] == .int(10))
        #expect(input["startSide"] == .string("RIGHT"))
        #expect(input["body"] == .string("Use a constant.\n```suggestion\nx\n```"))
    }

    @Test func singleCommentIsAReviewWithOneThread() throws {
        let anchor = ReviewAnchor(path: "a.go", side: .left, line: 3)
        let command = GitHubCommand.submitNewReview(
            pullRequestID: "PR_1", commit: "abc", event: .comment, body: "", comment: (anchor, "Why?"))
        let input = try input(command)
        #expect(input["event"] == .string("COMMENT"))
        #expect(input["commitOID"] == .string("abc"))
        #expect(input["body"] == nil)
        guard case .array(let threads) = input["threads"], case .object(let thread) = threads.first
        else {
            Issue.record("No thread")
            return
        }
        #expect(thread["side"] == .string("LEFT"))
        #expect(thread["startLine"] == nil)
    }

    @Test func submitAndResolve() throws {
        let submit = try input(
            .submitReview(reviewID: "PRR_1", event: .requestChanges, body: "Needs tests."))
        #expect(submit["event"] == .string("REQUEST_CHANGES"))
        #expect(
            try body(.setThreadResolved(threadID: "T", resolved: true)).query.contains(
                "resolveReviewThread"))
        #expect(
            try body(.setThreadResolved(threadID: "T", resolved: false)).query.contains(
                "unresolveReviewThread"))
        #expect(
            try body(.setFileViewed(pullRequestID: "PR", path: "a", viewed: false)).query.contains(
                "unmarkFileAsViewed"))
        #expect(
            try input(.replyToThread(threadID: "T", body: "Done", reviewID: nil))["pullRequestReviewId"]
                == nil)
        #expect(try input(.deleteReviewComment(commentID: "C"))["id"] == .string("C"))
        #expect(try body(.discardReview(reviewID: "R")).query.contains("DeletePullRequestReviewInput!"))
    }

    @Test func reviewCommentStartsAPendingReviewFirst() async throws {
        let page = try #require(
            try PullRequestPage.decode(
                Fixtures.data("pr-page-own"),
                reference: PullRequestReference(owner: "binbandit", name: "oh-fx", number: 974)))
        let runner = FakeRunner { command in
            let query = String(decoding: command.standardInput ?? Data(), as: UTF8.self)
            if query.contains("addPullRequestReviewThread") {
                return FakeRunner.success(
                    Data(#"{"data":{"addPullRequestReviewThread":{"thread":{"id":"T_1"}}}}"#.utf8))
            }
            return FakeRunner.success(
                Data(#"{"data":{"addPullRequestReview":{"pullRequestReview":{"id":"PRR_9"}}}}"#.utf8))
        }
        let cli = GitHubCLI(environment: [:], runner: runner)
        let reviewID = try await cli.addReviewComment(
            "Nit", at: ReviewAnchor(path: "a", side: .right, line: 1), on: page)

        #expect(reviewID == "PRR_9")
        #expect(runner.commands.count == 2)
        let second = String(decoding: runner.commands[1].standardInput ?? Data(), as: UTF8.self)
        #expect(second.contains("PRR_9"))
    }

    @Test func refusalsAreTyped() async throws {
        let page = try #require(
            try PullRequestPage.decode(
                Fixtures.data("pr-page-read-only"),
                reference: PullRequestReference(owner: "maximhq", name: "bifrost", number: 2584)))
        let runner = FakeRunner { _ in
            FakeRunner.failure(1, "GraphQL: Can not approve your own pull request (addPullRequestReview)")
        }
        await #expect(
            throws: GitHubError.permissionDenied(
                "GraphQL: Can not approve your own pull request (addPullRequestReview)")
        ) {
            try await GitHubCLI(environment: [:], runner: runner).submitReview(
                .approve, body: "", on: page)
        }
        #expect(
            GitHubError.permissionDenied("GraphQL: Can not approve your own pull request")
                .localizedDescription == "You can't approve your own pull request.")
        let merge = GitHubError.classify(
            exitCode: 1, stderr: "GraphQL: Resource not accessible by integration (mergePullRequest)")
        #expect(merge.localizedDescription == "Your account can't merge this pull request.")
        // Rate limits are 403s too, and stay rate limits.
        #expect(
            GitHubError.classify(exitCode: 1, stderr: "HTTP 403: API rate limit exceeded for user ID 1.")
                == .rateLimited("HTTP 403: API rate limit exceeded for user ID 1."))
    }

    @Test func mergeMatchesTheHeadTheUserSaw() async throws {
        let page = try #require(
            try PullRequestPage.decode(
                Fixtures.data("pr-page-own"),
                reference: PullRequestReference(owner: "binbandit", name: "oh-fx", number: 974)))
        let runner = FakeRunner { _ in FakeRunner.success(Data()) }
        try await GitHubCLI(environment: [:], runner: runner).merge(
            page, method: .squash, deleteBranch: true)
        #expect(
            runner.commands.first?.arguments == [
                "pr", "merge", "974", "--squash", "--delete-branch",
                "--match-head-commit=\(page.headRefOid)", "--repo=binbandit/oh-fx",
            ])
    }

    @Test func enterpriseReferencesTargetTheirHost() async throws {
        let url = try #require(URL(string: "https://ghe.example.com/team/app/pull/12/files"))
        let reference = try #require(PullRequestReference(url: url))
        #expect(
            reference
                == PullRequestReference(host: "ghe.example.com", owner: "team", name: "app", number: 12))
        let runner = FakeRunner { _ in
            FakeRunner.failure(1, "GraphQL: Could not resolve to a PullRequest with the number of 12.")
        }
        await #expect(throws: GitHubError.self) {
            try await GitHubCLI(environment: [:], runner: runner).pullRequestPage(reference)
        }
        #expect(runner.commands.first?.environment["GH_HOST"] == "ghe.example.com")
        let issue = try #require(URL(string: "https://github.com/a/b/issues/3"))
        #expect(PullRequestReference(url: issue) == nil)
    }

    @Test func agentPromptQuotesTheFeedback() {
        let prompt = ReviewAgentPrompt(
            reference: PullRequestReference(owner: "cli", name: "cli", number: 1), title: "Add download",
            branch: "dl",
            anchor: ReviewAnchor(path: "dl.go", side: .right, line: 9, startLine: 7), excerpt: "+a\n+b",
            notes: [.init(author: "babakks", body: "Name this better.\nMaybe `downloadAll`?")])
        #expect(prompt.text.contains("`dl.go`, lines 7–9 on the head side"))
        #expect(prompt.text.contains("```diff\n+a\n+b\n```"))
        #expect(prompt.text.contains("@babakks wrote:\n> Name this better.\n> Maybe `downloadAll`?"))
        #expect(prompt.text.hasSuffix(prompt.defaultRequest))
        var asked = prompt
        asked.request = "Rename it."
        #expect(asked.text.hasSuffix("Rename it."))
    }
}
