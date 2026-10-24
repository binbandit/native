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
        // Ask gh for status only. Its credentials stay inside gh, including when it uses Keychain.
        let status = try await GitHubCLI(environment: environment, host: target, runner: runner).authStatus()
        guard status.hosts[target]?.contains(where: { $0.active && $0.login == login && $0.state != .error }) == true
        else {
            throw GitHubError.notAuthenticated(
                "Activate @\(login) on \(target) with gh auth switch in a terminal, then check accounts in Native."
            )
        }
        command.environment["GH_HOST"] = target
        command.environment["GH_DEBUG"] = nil
        return command
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
            // Match gh's effective URLs, including insteadOf rewrites, before checking the active account.
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
