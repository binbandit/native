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

    @Test func selectedTokenOnlyEntersNativeCommands() async throws {
        let environment = ["GH_TOKEN": "terminal-token", "GITHUB_TOKEN": "terminal-fallback", "PATH": "/usr/bin"]
        let runner = FakeRunner { command in
            if command.arguments.starts(with: ["auth", "token"]) {
                #expect(command.environment["GH_TOKEN"] == nil)
                #expect(command.environment["GITHUB_TOKEN"] == nil)
                #expect(command.arguments.contains("--hostname=github.com"))
                #expect(command.arguments.contains("--user=sage-smudge"))
                return FakeRunner.success(Data("selected-token\n".utf8))
            }
            #expect(command.environment["GH_TOKEN"] == "selected-token")
            return FakeRunner.success(try Fixtures.data("api-user"))
        }
        let base = GitHubCLI(environment: environment, runner: runner)
        _ = try await base.selecting(.init(logins: ["github.com": "sage-smudge"])).currentUser()
        #expect(base.environment == environment)
        #expect(runner.commands.count == 2)
        #expect(!runner.commands.contains { $0.arguments.contains("switch") })
    }

    @Test func enterpriseAndPublicSelectionsStayOnTheirHosts() async throws {
        let runner = FakeRunner { command in
            if command.arguments.starts(with: ["auth", "token"]) {
                return FakeRunner.success(Data(command.arguments.last?.utf8 ?? "".utf8))
            }
            if command.environment["GH_HOST"] == "work.example.com" {
                #expect(command.environment["GH_ENTERPRISE_TOKEN"] == "--user=work")
                #expect(command.environment["GH_TOKEN"] == nil)
            } else {
                #expect(command.environment["GH_TOKEN"] == "--user=personal")
                #expect(command.environment["GH_ENTERPRISE_TOKEN"] == nil)
            }
            return FakeRunner.success(try Fixtures.data("api-user"))
        }
        let cli = GitHubCLI(environment: [:], runner: runner)
            .selecting(.init(logins: ["github.com": "personal", "work.example.com": "work"]))
        _ = try await cli.currentUser()
        _ = try await cli.targeting(host: "work.example.com").currentUser()
    }

    @Test func missingTokenNeverFallsBackOrLeaksOutput() async {
        let runner = FakeRunner { _ in FakeRunner.failure(1, "sensitive-output") }
        let cli = GitHubCLI(environment: ["GH_TOKEN": "terminal"], runner: runner)
            .selecting(.init(logins: ["github.com": "removed"]))
        do {
            _ = try await cli.currentUser()
            Issue.record("Expected an unavailable selected account")
        } catch {
            guard case .notAuthenticated(let message) = error else {
                Issue.record("Expected sign-in guidance")
                return
            }
            #expect(!message.contains("sensitive-output"))
        }
        #expect(runner.commands.count == 1)
    }

    @Test func authStatusDoesNotUseSelectedToken() async throws {
        let runner = FakeRunner { _ in FakeRunner.success(try Fixtures.data("auth-status-all-accounts")) }
        let cli = GitHubCLI(environment: [:], runner: runner).selecting(.init(logins: ["github.com": "sage-smudge"]))
        _ = try await cli.authStatus()
        #expect(runner.commands.count == 1)
        #expect(runner.commands[0].environment["GH_TOKEN"] == nil)
    }

    @Test func checkoutHostAndExplicitRemoteUseTheirOwnAccount() async throws {
        let runner = FakeRunner { command in
            if command.executable == "git" {
                return FakeRunner.success(Data("remote.origin.url\nhttps://work.example.com/team/repo.git\0".utf8))
            }
            if command.arguments.starts(with: ["auth", "token"]) {
                #expect(command.arguments.contains("--hostname=work.example.com"))
                return FakeRunner.success(Data("work-token".utf8))
            }
            #expect(command.environment["GH_ENTERPRISE_TOKEN"] == "work-token")
            return FakeRunner.success(Data("[]".utf8))
        }
        let cli = GitHubCLI(environment: [:], runner: runner)
            .selecting(.init(logins: ["github.com": "personal", "work.example.com": "work"]))
        _ = try await cli.pullRequests(in: .directory(URL(filePath: "/fixture")))
        _ = try await cli.pullRequests(in: .remote("work.example.com/team/repo"))
        #expect(runner.commands.filter { $0.executable == "git" }.count == 1)
    }

    @Test func unresolvedSSHAliasCannotBypassTheSelectedAccount() async {
        let runner = FakeRunner { command in
            if command.executable == "git" {
                return FakeRunner.success(Data("remote.origin.url\ngit@github-work:team/repo.git\0".utf8))
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
        #expect(runner.commands.count == 2)
    }

    @Test func ambiguousCheckoutFailsClosedUntilGhHasADefault() throws {
        let config =
            "remote.origin.url\nhttps://github.com/me/repo.git\0remote.upstream.url\nhttps://work.example.com/team/repo.git\0"
        #expect(throws: GitHubError.self) {
            try GitHubAccountHost.resolve(
                config: config, fallback: nil)
        }
        #expect(
            try GitHubAccountHost.resolve(
                config: config + "remote.upstream.gh-resolved\nbase\0",
                fallback: nil
            ) == "work.example.com")
    }
}
