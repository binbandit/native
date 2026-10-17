import Exec
import Foundation
import Testing
@testable import GitHub

/// `GitHubCLI` against a scripted runner that answers with captured gh output.
struct CLITests {
    let environment = ["PATH": "/usr/bin:/bin", "HOME": "/Users/someone"]

    @Test func inboxIsThreeSearchesAndOneStatusQuery() async throws {
        let runner = FakeRunner { command in
            switch (command.arguments[0], command.arguments.dropFirst(2).first) {
            case ("search", "--author=@me"?): FakeRunner.success(try Fixtures.data("search-authored"))
            case ("search", "--review-requested=@me"?): FakeRunner.success(try Fixtures.data("search-review-requested"))
            case ("search", _): FakeRunner.success(Data("[]".utf8))
            case ("api", _): FakeRunner.success(try Fixtures.data("graphql-pull-request-status"))
            default: FakeRunner.failure(1, "unexpected")
            }
        }
        let inbox = try await GitHubCLI(environment: environment, runner: runner).inbox()

        #expect(runner.commands.count == 4)
        #expect(runner.commands.allSatisfy { $0.executable == "gh" && $0.directory == nil })
        #expect(inbox.authored.count == 8)
        #expect(inbox.reviewRequested.count == 4)
        #expect(inbox.assigned.isEmpty)
        let enriched = try #require(inbox.authored.first)
        #expect(enriched.headRefName == "ai/tty-5-observer")
        #expect(enriched.checks?.state == .failing)
    }

    @Test func runsNonInteractivelyWithPackageManagerPaths() async throws {
        let runner = FakeRunner { _ in FakeRunner.success(Data("gh version 2.102.0 (2026-09-30)\n".utf8)) }
        let cli = GitHubCLI(environment: environment, runner: runner).targeting(host: "ghe.example.com")

        #expect(try await cli.version() == "gh version 2.102.0 (2026-09-30)")
        let command = try #require(runner.commands.first)
        #expect(command.environment["GH_PROMPT_DISABLED"] == "1")
        #expect(command.environment["GH_HOST"] == "ghe.example.com")
        let path = command.environment["PATH"]?.split(separator: ":").map(String.init) ?? []
        #expect(Array(path.prefix(2)) == ["/usr/bin", "/bin"])
        #expect(path.contains("/opt/homebrew/bin"))
        #expect(path.contains("/Users/someone/.nix-profile/bin"))
        #expect(path.filter { $0 == "/usr/bin" }.count == 1)
    }

    @Test func missingGhMeansNotInstalled() async throws {
        let cli = GitHubCLI(environment: environment, runner: FakeRunner { _ in throw CommandError.notFound("gh") })
        #expect(try await cli.availability() == .notInstalled)
    }

    @Test func signedOutAndOfflineAreReportedAsAvailability() async throws {
        let signedOut = GitHubCLI(environment: environment, runner: FakeRunner { _ in FakeRunner.success(Data(#"{"hosts":{}}"#.utf8)) })
        #expect(try await signedOut.availability() == .notAuthenticated)

        let offline = GitHubCLI(environment: environment, runner: FakeRunner { _ in
            FakeRunner.failure(1, "error connecting to api.github.com\ncheck your internet connection or https://githubstatus.com")
        })
        #expect(try await offline.availability() == .offline)

        let ready = try await GitHubCLI(environment: environment, runner: FakeRunner { _ in FakeRunner.success(try Fixtures.data("auth-status")) }).availability()
        guard case .ready(let accounts) = ready else {
            Issue.record("Expected ready, got \(ready)")
            return
        }
        #expect(accounts.map(\.login) == ["binbandit"])
    }

    @Test func pendingChecksExitWithEightButStillList() async throws {
        let runner = FakeRunner { _ in CommandResult(exitCode: 8, standardOutput: try Fixtures.data("pr-checks"), standardError: Data()) }
        let checks = try await GitHubCLI(environment: environment, runner: runner).checks(.number(972), in: .remote("binbandit/oh-fx"))
        #expect(!checks.isEmpty)
        #expect(runner.commands.first?.arguments.last == "--repo=binbandit/oh-fx")
    }

    @Test func noChecksIsAnEmptyList() async throws {
        let runner = FakeRunner { _ in FakeRunner.failure(1, "no checks reported on the 'feature' branch") }
        #expect(try await GitHubCLI(environment: environment, runner: runner).checks(.branch("feature"), in: .remote("a/b")).isEmpty)
    }

    @Test func branchWithoutPullRequestIsNil() async throws {
        let runner = FakeRunner { _ in FakeRunner.success(Data("[]".utf8)) }
        let folder = URL(filePath: "/work/tree", directoryHint: .isDirectory)
        #expect(try await GitHubCLI(environment: environment, runner: runner).pullRequest(forBranch: "feature", in: .directory(folder)) == nil)
        #expect(runner.commands.first?.directory == "/work/tree/")
    }

    @Test func createReturnsTheURLGhPrints() async throws {
        let runner = FakeRunner { _ in
            FakeRunner.success(Data("Warning: 2 uncommitted changes\nhttps://github.com/a/b/pull/42\n".utf8))
        }
        let folder = URL(filePath: "/work/tree", directoryHint: .isDirectory)
        let url = try await GitHubCLI(environment: environment, runner: runner)
            .createPullRequest(NewPullRequest(title: "Fix it", body: "Because.", head: "fix"), in: folder)

        #expect(url == URL(string: "https://github.com/a/b/pull/42"))
        let command = try #require(runner.commands.first)
        #expect(runner.commands.count == 1)
        #expect(command.standardInput == Data("Because.".utf8))
        #expect(command.arguments.contains("--head=fix"))
    }

    @Test func createFailureKeepsGhsReason() async {
        let runner = FakeRunner { _ in FakeRunner.failure(1, #"a pull request for branch "fix" into branch "main" already exists"#) }
        let folder = URL(filePath: "/work/tree", directoryHint: .isDirectory)
        await #expect(throws: GitHubError.failed(exitCode: 1, #"a pull request for branch "fix" into branch "main" already exists"#)) {
            try await GitHubCLI(environment: environment, runner: runner).createPullRequest(NewPullRequest(title: "T", body: "", head: "fix"), in: folder)
        }
    }

    @Test func runnerFailuresMapToGitHubErrors() async {
        let unreachable = GitHubCLI(environment: environment, runner: FakeRunner { _ in throw CommandError.unavailable("host is offline") })
        await #expect(throws: GitHubError.offline("host is offline")) { try await unreachable.currentUser() }

        let slow = GitHubCLI(environment: environment, runner: FakeRunner { _ in throw CommandError.timedOut("gh", after: .seconds(30)) })
        await #expect(throws: GitHubError.timedOut) { try await slow.currentUser() }
    }
}
