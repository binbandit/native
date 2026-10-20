import Exec
import Foundation

/// The user's own `gh`: their logins, hosts (GitHub Enterprise included), aliases and config all
/// apply, and Native never handles a token. Every read uses `--json` and decodes it; nothing parses
/// gh's human-readable output.
///
/// gh runs through a `CommandRunner`, so it can run on whichever machine hosts the project. Pass
/// that machine's login-shell environment: gh is found on its PATH, and uses it to find `git`.
public struct GitHubCLI: Sendable {
    /// The environment gh runs with, before Native's non-interactive overrides.
    public let environment: [String: String]
    /// The host commands target, as `GH_HOST`; `nil` for gh's default.
    public let host: String?
    public let runner: any CommandRunner

    public init(environment: [String: String], host: String? = nil, runner: any CommandRunner) {
        self.environment = environment
        self.host = host
        self.runner = runner
    }

    #if os(macOS)
    /// gh on this Mac.
    public init(environment: [String: String], host: String? = nil) {
        self.init(environment: environment, host: host, runner: LocalCommandRunner())
    }
    #endif

    /// The same gh, aimed at another host.
    public func targeting(host: String?) -> GitHubCLI {
        GitHubCLI(environment: environment, host: host, runner: runner)
    }

    /// Where package managers put gh, appended to the PATH: an app's fallback environment (when the
    /// login shell couldn't be read) may lack them.
    static let wellKnownDirectories = [
        "/opt/homebrew/bin", "/usr/local/bin", "/opt/local/bin", "/run/current-system/sw/bin", "/usr/bin", "/bin",
    ]

    /// What gh runs with: the given environment, made non-interactive and quiet.
    var processEnvironment: [String: String] {
        var environment = environment
        environment["GH_PROMPT_DISABLED"] = "1"
        environment["GH_NO_UPDATE_NOTIFIER"] = "1"
        environment["GH_NO_EXTENSION_UPDATE_NOTIFIER"] = "1"
        environment["GH_SPINNER_DISABLED"] = "1"
        environment["NO_COLOR"] = "1"
        var path = (environment["PATH"] ?? "").split(separator: ":").map(String.init)
        var directories = Self.wellKnownDirectories
        if let home = environment["HOME"] {
            directories.append("\(home)/.nix-profile/bin")
        }
        path += directories.filter { !path.contains($0) }
        environment["PATH"] = path.joined(separator: ":")
        if let host {
            environment["GH_HOST"] = host
        }
        return environment
    }

    /// The command the runner executes for a gh invocation.
    func command(for command: GitHubCommand) -> Command {
        Command(
            "gh",
            command.arguments,
            in: command.directory?.path(percentEncoded: false),
            environment: processEnvironment,
            standardInput: command.input,
            timeout: command.timeout
        )
    }

    // MARK: - Running

    /// Runs a command and returns its stdout, throwing gh's classified failure otherwise.
    public func run(
        _ command: GitHubCommand, acceptingExitCodes accepted: Set<Int32> = [0]
    ) async throws(GitHubError) -> Data {
        let result: CommandResult
        do {
            result = try await runner.run(self.command(for: command))
        } catch CommandError.notFound {
            throw .notInstalled
        } catch CommandError.timedOut {
            throw .timedOut
        } catch CommandError.unavailable(let reason) {
            throw .offline(reason)
        } catch is CancellationError {
            throw .cancelled
        } catch {
            throw .failed(exitCode: -1, error.localizedDescription)
        }
        if Task.isCancelled {
            throw .cancelled
        }
        guard accepted.contains(result.exitCode) else {
            throw GitHubError.classify(exitCode: result.exitCode, stderr: result.errorOutput)
        }
        return result.standardOutput
    }

    private func decode<T: Decodable>(_ type: T.Type, from command: GitHubCommand) async throws(GitHubError) -> T {
        try GitHubJSON.decode(type, from: try await run(command))
    }

    // MARK: - Account

    /// gh's version line, e.g. `gh version 2.62.0 (2024-11-14)`. Doesn't touch the network.
    public func version() async throws(GitHubError) -> String {
        let output = try await run(.version)
        return String(decoding: output, as: UTF8.self).split(separator: "\n").first.map(String.init) ?? ""
    }

    /// The account gh uses for each host, with whether its token works.
    public func authStatus() async throws(GitHubError) -> AuthStatus {
        try await decode(AuthStatus.self, from: .authStatus(host: host))
    }

    /// Whether GitHub features can be used, without throwing for the states the UI explains.
    public func availability() async throws(GitHubError) -> GitHubAvailability {
        let status: AuthStatus
        do {
            status = try await authStatus()
        } catch .notInstalled {
            return .notInstalled
        } catch .notAuthenticated {
            return .notAuthenticated
        } catch .offline {
            return .offline
        }
        let accounts = status.activeAccounts
        let working = accounts.filter { $0.state == .success }
            .sorted { ($0.host == "github.com" ? 0 : 1, $0.host) < ($1.host == "github.com" ? 0 : 1, $1.host) }
        if !working.isEmpty {
            return .ready(accounts: working)
        }
        if !accounts.isEmpty, accounts.allSatisfy({ $0.state == .timeout }) {
            return .offline
        }
        return .notAuthenticated
    }

    public func currentUser() async throws(GitHubError) -> GitHubUser {
        try await decode(GitHubUser.self, from: .currentUser)
    }

    public func rateLimit() async throws(GitHubError) -> RateLimit {
        try await decode(RateLimit.self, from: .rateLimit)
    }

    // MARK: - Repositories

    /// The GitHub repository a folder's git remotes point at (or the one named).
    public func repository(_ location: RepositoryLocation) async throws(GitHubError) -> GitHubRepository {
        try await decode(GitHubRepository.self, from: .repository(location))
    }

    // MARK: - Pull requests

    public func search(_ search: PullRequestSearch) async throws(GitHubError) -> [PullRequestSearchResult] {
        try await decode([PullRequestSearchResult].self, from: .search(search))
    }

    /// Branches, review decision, mergeability and CI for pull requests found by `search`, keyed by
    /// node id. One GraphQL request per 100; ids that no longer resolve are left out.
    public func pullRequestStatuses(ids: [String]) async throws(GitHubError) -> [String: PullRequestStatus] {
        var statuses = [String: PullRequestStatus]()
        for start in stride(from: 0, to: ids.count, by: 100) {
            let batch = Array(ids[start..<min(start + 100, ids.count)])
            let response = try await decode(PullRequestStatus.Response.self, from: .pullRequestStatuses(ids: batch))
            for case let status? in response.data.nodes.map({ $0?.status }) {
                statuses[status.id] = status
            }
        }
        return statuses
    }

    /// The user's open pull requests on this host: authored, awaiting their review, and assigned,
    /// each with CI and review state. Three searches (GitHub allows 30 a minute) and one GraphQL
    /// request.
    public func inbox(limit: Int = 50) async throws(GitHubError) -> PullRequestInbox {
        async let authored = result { () async throws(GitHubError) in
            try await search(PullRequestSearch(.author, limit: limit))
        }
        async let reviewRequested = result { () async throws(GitHubError) in
            try await search(PullRequestSearch(.reviewRequested, limit: limit))
        }
        async let assigned = result { () async throws(GitHubError) in
            try await search(PullRequestSearch(.assignee, limit: limit))
        }
        let sections = try await (authored.get(), reviewRequested.get(), assigned.get())

        var ids = [String]()
        var seen = Set<String>()
        for result in sections.0 + sections.1 + sections.2 where seen.insert(result.id).inserted {
            ids.append(result.id)
        }
        let statuses = try await pullRequestStatuses(ids: ids)
        func summaries(_ results: [PullRequestSearchResult]) -> [PullRequestSummary] {
            results.map { PullRequestSummary($0, status: statuses[$0.id]) }
        }
        return PullRequestInbox(
            authored: summaries(sections.0),
            reviewRequested: summaries(sections.1),
            assigned: summaries(sections.2),
            fetchedAt: .now
        )
    }

    /// `gh pr list` for one repository.
    public func pullRequests(
        _ filter: PullRequestListFilter = PullRequestListFilter(), in location: RepositoryLocation
    ) async throws(GitHubError) -> [PullRequest] {
        try await decode([PullRequest].self, from: .listPullRequests(filter, in: location))
    }

    public func pullRequest(
        _ pullRequest: PullRequestSelector, in location: RepositoryLocation
    ) async throws(GitHubError) -> PullRequest {
        try await decode(PullRequest.self, from: .viewPullRequest(pullRequest, in: location))
    }

    /// A branch's pull requests: the newest open one (else the newest) and the rest; `nil` when the
    /// branch has none.
    public func pullRequests(
        forBranch branch: String, in location: RepositoryLocation
    ) async throws(GitHubError) -> BranchPullRequests? {
        BranchPullRequests(
            try await pullRequests(PullRequestListFilter(state: .all, head: branch, limit: 10), in: location))
    }

    /// Every check on the pull request's head commit; empty when it has none.
    public func checks(
        _ pullRequest: PullRequestSelector, in location: RepositoryLocation
    ) async throws(GitHubError) -> [PullRequestCheck] {
        do {
            // gh exits with 8 while checks are pending, after printing them.
            return try GitHubJSON.decode(
                [PullRequestCheck].self,
                from: try await run(.checks(pullRequest, in: location), acceptingExitCodes: [0, 8]))
        } catch .failed(_, let message) where message.contains("no checks reported") {
            return []
        }
    }

    /// Opens the pull request in gh's configured browser. When the URL is at hand, opening it
    /// directly (`NSWorkspace`) is faster and needs no subprocess.
    public func openInBrowser(
        _ pullRequest: PullRequestSelector, in location: RepositoryLocation
    ) async throws(GitHubError) {
        _ = try await run(.openInBrowser(pullRequest, in: location))
    }

    // MARK: - Changes (each needs an explicit user action)

    /// Opens a pull request from an already-pushed branch and returns its URL.
    public func createPullRequest(_ pullRequest: NewPullRequest, in directory: URL) async throws(GitHubError) -> URL {
        let output = String(decoding: try await run(.createPullRequest(pullRequest, in: directory)), as: UTF8.self)
        // gh prints the new pull request's URL as its last line when not attached to a terminal.
        let lines = output.split(whereSeparator: \.isNewline).map { $0.trimmingCharacters(in: .whitespaces) }
        guard let line = lines.last(where: { $0.hasPrefix("https://") || $0.hasPrefix("http://") }),
            let url = URL(string: line)
        else {
            throw .unexpectedOutput(output)
        }
        return url
    }

    /// Checks the pull request out in `directory`, changing its working tree. Use a fresh worktree;
    /// see `GitHubCommand.checkout`.
    public func checkout(
        _ pullRequest: PullRequestSelector, in directory: URL, localBranch: String? = nil, detach: Bool = false
    ) async throws(GitHubError) {
        _ = try await run(.checkout(pullRequest, in: directory, localBranch: localBranch, detach: detach))
    }

    /// Merges the pull request. Pass a `.remote` location so `deleteBranch` only deletes the remote
    /// branch and leaves local checkouts alone.
    public func merge(
        _ pullRequest: PullRequestSelector, in location: RepositoryLocation, method: MergeMethod,
        deleteBranch: Bool = false, matchHeadCommit: String? = nil, admin: Bool = false
    ) async throws(GitHubError) {
        _ = try await run(
            .merge(
                pullRequest, in: location, method: method, deleteBranch: deleteBranch, matchHeadCommit: matchHeadCommit,
                admin: admin))
    }
}

extension GitHubCLI {
    public func close(_ pullRequest: PullRequestSelector, in location: RepositoryLocation) async throws(GitHubError) {
        _ = try await run(.close(pullRequest, in: location))
    }

    public func reopen(_ pullRequest: PullRequestSelector, in location: RepositoryLocation) async throws(GitHubError) {
        _ = try await run(.reopen(pullRequest, in: location))
    }

    /// Adds a comment to the pull request's conversation.
    public func comment(
        _ body: String, on pullRequest: PullRequestSelector, in location: RepositoryLocation
    ) async throws(GitHubError) {
        _ = try await run(.comment(body, on: pullRequest, in: location))
    }
}

/// Captures a typed-throwing call as a `Result`, so `async let` keeps the error type.
private func result<T>(_ body: () async throws(GitHubError) -> T) async -> Result<T, GitHubError> {
    do {
        return .success(try await body())
    } catch {
        return .failure(error)
    }
}
