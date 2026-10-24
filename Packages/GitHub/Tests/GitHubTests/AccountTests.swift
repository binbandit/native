import Exec
import Foundation
import Testing

@testable import GitHub

struct AccountTests {
    @Test func listsInactiveAccountsAndKeepsGhsDefault() async throws {
        let runner = FakeRunner { _ in FakeRunner.success(try Fixtures.data("auth-status-all-accounts")) }
        let status = try await GitHubCLI(environment: [:], runner: runner).authStatus()
        #expect(status.hosts["github.com"]?.count == 3)
        #expect(GitHubAccountSelection().accounts(in: status).map(\.login) == ["binbandit"])
        #expect(!runner.commands[0].arguments.contains("--active"))
        #expect(
            GitHubAccountSelection(logins: ["github.com": "sage-smudge"]).accounts(in: status).first?.login
                == "sage-smudge")
        #expect(GitHubAccountSelection(logins: ["github.com": "removed"]).accounts(in: status).first?.state == .error)
    }

    @Test func defaultsArePinnedWithoutPersistingOrReplacingEnvironmentCredentials() throws {
        let status = try JSONDecoder().decode(AuthStatus.self, from: Fixtures.data("auth-status-all-accounts"))
        let choices = GitHubAccountSelection()
        #expect(choices.includingDefaults(from: status).logins == ["github.com": "binbandit"])
        #expect(choices.logins.isEmpty)
        let environmentAccount = AuthStatus(hosts: [
            "github.com": [
                .init(host: "github.com", login: "environment", active: true, state: .success, tokenSource: "GH_TOKEN")
            ]
        ])
        #expect(choices.includingDefaults(from: environmentAccount).logins.isEmpty)
        let chosenEnvironment = GitHubAccountSelection(logins: ["github.com": "environment"])
        #expect(chosenEnvironment.includingDefaults(from: environmentAccount).logins.isEmpty)
        #expect(chosenEnvironment.logins["github.com"] == "environment")
    }

    @Test func activeAccountUsesGhWithoutExtractingCredentials() async throws {
        let environment = ["GH_TOKEN": "terminal-token", "GITHUB_TOKEN": "terminal-fallback", "PATH": "/usr/bin"]
        let runner = FakeRunner { command in
            #expect(command.environment["GH_TOKEN"] == "terminal-token")
            if command.arguments.starts(with: ["auth", "status"]) {
                return Self.status(host: "github.com", login: "personal")
            }
            return FakeRunner.success(try Fixtures.data("api-user"))
        }
        let base = GitHubCLI(environment: environment, runner: runner)
        _ = try await base.selecting(.init(logins: ["github.com": "personal"])).currentUser()
        #expect(base.environment == environment)
        #expect(runner.commands.count == 2)
        #expect(!runner.commands.contains { $0.arguments.contains("token") || $0.arguments.contains("switch") })
    }

    @Test func enterpriseAndPublicSelectionsStayOnTheirHosts() async throws {
        let runner = FakeRunner { command in
            let host = command.environment["GH_HOST"] ?? "github.com"
            #expect(command.environment["GH_ENTERPRISE_TOKEN"] == nil)
            #expect(command.environment["GH_TOKEN"] == nil)
            if command.arguments.starts(with: ["auth", "status"]) {
                return Self.status(host: host, login: host == "github.com" ? "personal" : "work")
            }
            return FakeRunner.success(try Fixtures.data("api-user"))
        }
        let cli = GitHubCLI(environment: [:], runner: runner)
            .selecting(.init(logins: ["github.com": "personal", "work.example.com": "work"]))
        _ = try await cli.currentUser()
        _ = try await cli.targeting(host: "work.example.com").currentUser()
    }

    @Test(arguments: ["inactive", "removed"])
    func unavailableChoiceNeverFallsBackToAnotherAccount(login: String) async {
        let runner = FakeRunner { _ in
            FakeRunner.success(
                Data(
                    "{\"hosts\":{\"github.com\":[{\"host\":\"github.com\",\"login\":\"active\",\"active\":true,\"state\":\"SUCCESS\"},{\"host\":\"github.com\",\"login\":\"inactive\",\"active\":false,\"state\":\"SUCCESS\"}]}}"
                        .utf8))
        }
        let cli = GitHubCLI(environment: [:], runner: runner)
            .selecting(.init(logins: ["github.com": login]))
        do {
            _ = try await cli.currentUser()
            Issue.record("Expected an unavailable selected account")
        } catch {
            guard case .notAuthenticated(let message) = error else {
                Issue.record("Expected sign-in guidance")
                return
            }
            #expect(message.contains("gh auth switch"))
        }
        #expect(runner.commands.count == 1)
        #expect(runner.commands.first?.arguments.starts(with: ["auth", "status"]) == true)
    }

    @Test func authStatusDoesNotRetrieveCredentials() async throws {
        let runner = FakeRunner { _ in FakeRunner.success(try Fixtures.data("auth-status-all-accounts")) }
        let cli = GitHubCLI(environment: [:], runner: runner).selecting(.init(logins: ["github.com": "sage-smudge"]))
        _ = try await cli.authStatus()
        #expect(runner.commands.count == 1)
        #expect(runner.commands[0].environment["GH_TOKEN"] == nil)
    }

    @Test func checkoutHostAndExplicitRemoteUseTheirOwnAccount() async throws {
        let runner = FakeRunner { command in
            if command.executable == "git" {
                return FakeRunner.success(Data("origin\thttps://work.example.com/team/repo.git (fetch)\n".utf8))
            }
            if command.arguments.starts(with: ["auth", "status"]) {
                #expect(command.environment["GH_HOST"] == "work.example.com")
                return Self.status(host: "work.example.com", login: "work")
            }
            #expect(command.environment["GH_ENTERPRISE_TOKEN"] == nil)
            return FakeRunner.success(Data("[]".utf8))
        }
        let cli = GitHubCLI(environment: [:], runner: runner)
            .selecting(.init(logins: ["github.com": "personal", "work.example.com": "work"]))
        _ = try await cli.pullRequests(in: .directory(URL(filePath: "/fixture")))
        _ = try await cli.pullRequests(in: .remote("work.example.com/team/repo"))
        #expect(runner.commands.filter { $0.executable == "git" }.count == 2)
    }

    @Test func unresolvedSSHAliasCannotBypassTheSelectedAccount() async {
        let runner = FakeRunner { command in
            if command.executable == "git" {
                return FakeRunner.success(Data("origin\tgit@github-work:team/repo.git (fetch)\n".utf8))
            }
            if command.arguments.starts(with: ["auth", "status"]) {
                return FakeRunner.success(try Fixtures.data("auth-status-all-accounts"))
            }
            Issue.record("An unresolved host must not perform the request as gh's default account")
            return FakeRunner.success(Data("[]".utf8))
        }
        let cli = GitHubCLI(environment: [:], runner: runner)
            .selecting(.init(logins: ["github.com": "sage-smudge"]))
        await #expect(throws: GitHubError.self) {
            try await cli.pullRequests(in: .directory(URL(filePath: "/fixture")))
        }
        #expect(runner.commands.count == 3)
    }

    @Test func effectiveRemoteURLChecksTheRewrittenEnterpriseAccount() async throws {
        let runner = FakeRunner { command in
            if command.executable == "git" {
                if command.arguments == ["remote", "-v"] {
                    return FakeRunner.success(
                        Data(
                            "origin\thttps://new.example.com/team/repo.git (fetch)\norigin\thttps://new.example.com/team/repo.git (push)\n"
                                .utf8))
                }
                return FakeRunner.success(Data("remote.origin.url\nhttps://old.example.com/team/repo.git\0".utf8))
            }
            if command.arguments.starts(with: ["auth", "status"]) {
                #expect(command.environment["GH_HOST"] == "new.example.com")
                return Self.status(host: "new.example.com", login: "new-account")
            }
            #expect(command.environment["GH_ENTERPRISE_TOKEN"] == nil)
            #expect(command.environment["GH_HOST"] == "new.example.com")
            return FakeRunner.success(Data("[]".utf8))
        }
        let cli = GitHubCLI(environment: [:], runner: runner)
            .selecting(.init(logins: ["old.example.com": "old-account", "new.example.com": "new-account"]))
        _ = try await cli.pullRequests(in: .directory(URL(filePath: "/fixture")))
    }

    @Test func repositoryEnvironmentDoesNotOverrideAPIOrExplicitRepositoryHosts() async throws {
        let runner = FakeRunner { command in
            if command.arguments.starts(with: ["auth", "status"]) {
                #expect(command.environment["GH_HOST"] == "github.com")
                return Self.status(host: "github.com", login: "personal")
            }
            #expect(command.environment["GH_TOKEN"] == nil)
            #expect(command.environment["GH_ENTERPRISE_TOKEN"] == nil)
            return FakeRunner.success(Data("{}".utf8))
        }
        let cli = GitHubCLI(environment: ["GH_REPO": "work.example.com/team/repo"], runner: runner)
            .selecting(.init(logins: ["github.com": "personal", "work.example.com": "work"]))
            .targeting(host: "github.com")
        for command: GitHubCommand in [
            .currentUser, .search(PullRequestSearch(.author)),
            .listPullRequests(.init(), in: .remote("owner/repo")), .repository(.remote("owner/repo")),
        ] {
            _ = try await cli.run(command)
        }
    }

    @Test func ambiguousCheckoutFailsClosedUntilGhHasADefault() throws {
        let remotes =
            "origin\thttps://github.com/me/repo.git (fetch)\nupstream\thttps://work.example.com/team/repo.git (fetch)\n"
        #expect(throws: GitHubError.self) {
            try GitHubAccountHost.resolve(
                remotes: remotes, config: "", fallback: nil)
        }
        #expect(
            try GitHubAccountHost.resolve(
                remotes: remotes, config: "remote.upstream.gh-resolved\nbase\0",
                fallback: nil
            ) == "work.example.com")
    }

    @Test func repositoryEnvironmentStillAppliesToCheckoutCommands() async throws {
        let runner = FakeRunner { command in
            #expect(command.executable == "gh")
            if command.arguments.starts(with: ["auth", "status"]) {
                #expect(command.environment["GH_HOST"] == "work.example.com")
                return Self.status(host: "work.example.com", login: "work")
            }
            #expect(command.environment["GH_HOST"] == "work.example.com")
            #expect(command.environment["GH_ENTERPRISE_TOKEN"] == nil)
            return FakeRunner.success(Data("[]".utf8))
        }
        let cli = GitHubCLI(environment: ["GH_REPO": "work.example.com/team/repo"], runner: runner)
            .selecting(.init(logins: ["github.com": "personal", "work.example.com": "work"]))
        _ = try await cli.pullRequests(in: .directory(URL(filePath: "/fixture")))
    }

    @Test func searchURLIsAKeywordNotACredentialHost() async throws {
        let runner = FakeRunner { command in
            if command.arguments.starts(with: ["auth", "status"]) {
                #expect(command.environment["GH_HOST"] == "github.com")
                return Self.status(host: "github.com", login: "personal")
            }
            #expect(command.environment["GH_TOKEN"] == nil)
            return FakeRunner.success(Data("[]".utf8))
        }
        let cli = GitHubCLI(environment: [:], runner: runner)
            .selecting(.init(logins: ["github.com": "personal", "work.example.com": "work"]))
        var search = PullRequestSearch(.author)
        search.keywords = "https://work.example.com/team/repo/pull/1"
        _ = try await cli.search(search)
    }
    private static func status(host: String, login: String) -> CommandResult {
        let row: [String: Any] = ["host": host, "login": login, "active": true, "state": "SUCCESS"]
        let data = (try? JSONSerialization.data(withJSONObject: ["hosts": [host: [row]]])) ?? Data()
        return FakeRunner.success(data)
    }
}
