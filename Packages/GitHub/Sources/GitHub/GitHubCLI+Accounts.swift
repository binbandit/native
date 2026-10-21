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
        guard let login = accountSelection.logins[target] else { return command }
        let token = try await accountToken(login: login, host: target)
        let key = target == "github.com" || target.hasSuffix(".ghe.com") ? "GH_TOKEN" : "GH_ENTERPRISE_TOKEN"
        command.environment[key] = token
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
        // URL selectors override the checkout, including `pr checkout <url>`.
        if let urlHost = request.arguments.compactMap({ argument -> String? in
            guard argument.hasPrefix("https://") else { return nil }
            return URL(string: argument)?.host()
        }).first {
            return urlHost.lowercased()
        }
        if let host = request.repositoryHost { return host }
        if let repo = environment["GH_REPO"] { return GitHubCommand.host(of: repo) }
        if let directory = request.directory {
            // Read git's config locally, including gh's chosen base remote. No GitHub request may
            // run with another account merely to discover which host a private checkout uses.
            let result = try await runner.run(
                Command(
                    "git", ["config", "--null", "--get-regexp", "^remote\\..*\\.(url|gh-resolved)$"],
                    in: directory.path(percentEncoded: false), environment: environment, timeout: .seconds(10)))
            guard result.succeeded || result.exitCode == 1 else {
                throw GitHubError.notARepository("Couldn't read this checkout's GitHub remotes.")
            }
            return try GitHubAccountHost.resolve(
                config: result.output,
                fallback: host ?? environment["GH_HOST"])
        }
        return host ?? environment["GH_HOST"] ?? "github.com"
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
        command.repositoryHost = repository.split(separator: "/").count >= 3 ? Self.host(of: repository) : nil
        return command
    }

    static func host(of repository: String) -> String {
        if let host = URL(string: repository)?.host() { return host.lowercased() }
        let parts = repository.split(separator: "/")
        return parts.count >= 3 ? String(parts[0]).lowercased() : "github.com"
    }
}
