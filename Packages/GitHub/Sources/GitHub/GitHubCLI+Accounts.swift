import Exec
import Foundation

extension GitHubCLI {
    /// A copy using Native's choices. No gh config, keychain entry or terminal environment changes.
    public func selecting(_ selection: GitHubAccountSelection) -> GitHubCLI {
        var cli = self
        cli.accountSelection = selection
        return cli
    }

    func authenticatedCommand(for request: GitHubCommand) async throws -> Command {
        var command = command(for: request)
        // Listing accounts must see gh's real state, never the override from a previous choice.
        guard !accountSelection.logins.isEmpty, request.arguments.first != "auth",
            request.arguments != ["--version"]
        else { return command }

        let target = try await accountHost(for: request, environment: command.environment)
        guard let login = accountSelection.logins[target] else {
            if request.directory != nil {
                // gh can translate SSH aliases that git's raw config doesn't expose. Never let
                // an unresolved alias silently bypass Native's choice and use gh's active login.
                let status = try await GitHubCLI(environment: environment, runner: runner).authStatus()
                guard status.hosts[target]?.contains(where: \.active) == true else {
                    throw GitHubError.notARepository(
                        "This remote doesn't identify a signed-in GitHub host. Use a remote URL with the GitHub hostname, then try again."
                    )
                }
            }
            return command
        }
        let token = try await accountToken(login: login, host: target)
        let key = target == "github.com" || target.hasSuffix(".ghe.com") ? "GH_TOKEN" : "GH_ENTERPRISE_TOKEN"
        command.environment[key] = token
        // gh filters translated remotes by GH_HOST. Pin it to the credential's host so a further
        // SSH alias translation cannot redirect an enterprise credential to another server.
        command.environment["GH_HOST"] = target
        command.environment["GH_DEBUG"] = nil
        return command
    }

    /// Never returns token output as an error, and never caches or persists it.
    private func accountToken(login: String, host: String) async throws -> String {
        var environment = processEnvironment
        for key in ["GH_TOKEN", "GITHUB_TOKEN", "GH_ENTERPRISE_TOKEN", "GITHUB_ENTERPRISE_TOKEN", "GH_DEBUG"] {
            environment[key] = nil
        }
        let result = try await runner.run(
            Command(
                "gh", ["auth", "token", "--hostname=\(host)", "--user=\(login)"],
                environment: environment, timeout: .seconds(10)))
        let token = result.output.trimmingCharacters(in: .whitespacesAndNewlines)
        guard result.succeeded, !token.isEmpty else {
            throw GitHubError.notAuthenticated("Sign in to \(login) on \(host) again, or choose another account.")
        }
        return token
    }

    private func accountHost(for request: GitHubCommand, environment: [String: String]) async throws -> String {
        let defaultHost = (host ?? environment["GH_HOST"] ?? "github.com").lowercased()
        // These commands do not infer a repository from GH_REPO. Search keywords can also be URLs.
        if ["api", "search"].contains(request.arguments.first ?? "") { return defaultHost }
        // URL selectors override the checkout, including `pr checkout <url>`.
        if request.arguments.first == "pr", request.arguments.count > 2,
            let urlHost = URL(string: request.arguments[2])?.host()
        {
            return urlHost.lowercased()
        }
        if let repo = request.repository { return GitHubCommand.host(of: repo, defaultHost: defaultHost) }
        if let directory = request.directory {
            if let repo = environment["GH_REPO"] { return GitHubCommand.host(of: repo, defaultHost: defaultHost) }
            // Match gh's effective URLs, including insteadOf rewrites, before choosing a token.
            let remotes = try await runner.run(
                Command(
                    "git", ["remote", "-v"], in: directory.path(percentEncoded: false),
                    environment: environment, timeout: .seconds(10)))
            let result = try await runner.run(
                Command(
                    "git", ["config", "--null", "--get-regexp", "^remote\\..*\\.gh-resolved$"],
                    in: directory.path(percentEncoded: false), environment: environment, timeout: .seconds(10)))
            guard remotes.succeeded, result.succeeded || result.exitCode == 1 else {
                throw GitHubError.notARepository("Couldn't read this checkout's GitHub remotes.")
            }
            return try GitHubAccountHost.resolve(
                remotes: remotes.output, config: result.output, fallback: defaultHost)
        }
        return defaultHost
    }
}

extension GitHubCommand {
    public static func userProfile(login: String) -> GitHubCommand {
        let encoded =
            login.addingPercentEncoding(withAllowedCharacters: .alphanumerics.union(CharacterSet(charactersIn: "-")))
            ?? login
        return GitHubCommand(["api", "users/\(encoded)"])
    }

    func targetingRepository(_ repository: String) -> GitHubCommand {
        var command = self
        command.repository = repository
        return command
    }

    static func host(of repository: String, defaultHost: String = "github.com") -> String {
        if let host = URL(string: repository)?.host() { return host.lowercased() }
        let parts = repository.split(separator: "/")
        return parts.count >= 3 ? String(parts[0]).lowercased() : defaultHost
    }
}
