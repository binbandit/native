import Foundation

/// One `gh` invocation as plain data. Building commands is separate from running them, so every
/// argument list, including the mutating ones, is testable without a network or a login.
public struct GitHubCommand: Sendable, Hashable {
    /// Arguments after `gh`. User-supplied values use `--flag=value`, so a value starting with `-`
    /// can't be read as a flag.
    public var arguments: [String]
    /// Where gh runs; it finds the repository from this folder's git remotes.
    public var directory: URL?
    /// Explicit repository host, before gh resolves a local checkout.
    var repositoryHost: String?
    /// Written to gh's stdin: request bodies and pull request bodies, which can be long.
    public var input: Data?
    /// Whether it changes anything on GitHub, in a remote or in a working tree.
    public var isMutating: Bool
    public var timeout: Duration

    init(
        _ arguments: [String], in location: RepositoryLocation? = nil, input: Data? = nil, isMutating: Bool = false,
        timeout: Duration = .seconds(30)
    ) {
        self.arguments = arguments
        self.input = input
        self.isMutating = isMutating
        self.timeout = timeout
        switch location {
        case .directory(let url):
            directory = url
        case .remote(let repository):
            directory = nil
            self.arguments.append("--repo=\(repository)")
            repositoryHost = repository.split(separator: "/").count >= 3 ? Self.host(of: repository) : nil
        case nil:
            directory = nil
        }
    }
}

// MARK: - Reads

extension GitHubCommand {
    public static let version = GitHubCommand(["--version"], timeout: .seconds(10))

    /// Every signed-in account per host. gh checks each token against its host, so this needs the
    /// network.
    public static func authStatus(host: String? = nil) -> GitHubCommand {
        GitHubCommand(["auth", "status", "--json", "hosts"] + (host.map { ["--hostname=\($0)"] } ?? []))
    }

    public static let currentUser = GitHubCommand(["api", "user"])

    public static let rateLimit = GitHubCommand(["api", "rate_limit"])

    public static func repository(_ location: RepositoryLocation) -> GitHubCommand {
        switch location {
        case .directory:
            GitHubCommand(["repo", "view", "--json", GitHubRepository.fields], in: location)
        case .remote(let repository):
            // `repo view` takes the repository as its argument rather than `--repo`.
            GitHubCommand(["repo", "view", repository, "--json", GitHubRepository.fields])
                .targetingRepository(repository)
        }
    }

    public static func search(_ search: PullRequestSearch) -> GitHubCommand {
        let involvement =
            switch search.involvement {
            case .author: "--author=\(search.user)"
            case .reviewRequested: "--review-requested=\(search.user)"
            case .assignee: "--assignee=\(search.user)"
            }
        var arguments = [
            "search", "prs", involvement,
            "--state=\(search.state.rawValue)",
            // Nobody can act on pull requests in archived repositories.
            "--archived=false",
            "--sort=updated", "--order=desc",
            "--limit=\(search.limit)",
            "--json", PullRequestSearchResult.fields,
        ]
        arguments += search.repositories.map { "--repo=\($0)" }
        if let keywords = search.keywords?.trimmingCharacters(in: .whitespaces), !keywords.isEmpty {
            // After `--`, so a qualifier like `-label:wip` isn't read as a flag.
            arguments += ["--", keywords]
        }
        return GitHubCommand(arguments)
    }

    /// One GraphQL request for up to 100 pull requests by node id. `gh api` can't pass an array
    /// variable as a flag, so the whole request goes through stdin.
    public static func pullRequestStatuses(ids: [String]) -> GitHubCommand {
        struct Request: Encodable {
            struct Variables: Encodable {
                var ids: [String]
            }

            var query: String
            var variables: Variables
        }
        // Encoding plain strings can't fail.
        let body =
            (try? JSONEncoder().encode(Request(query: PullRequestStatus.query, variables: .init(ids: ids)))) ?? Data()
        return GitHubCommand(["api", "graphql", "--input", "-"], input: body)
    }

    public static func listPullRequests(
        _ filter: PullRequestListFilter, in location: RepositoryLocation
    ) -> GitHubCommand {
        var arguments = ["pr", "list", "--state=\(filter.state.rawValue)", "--limit=\(filter.limit)"]
        if let author = filter.author { arguments.append("--author=\(author)") }
        if let head = filter.head { arguments.append("--head=\(head)") }
        if let search = filter.search { arguments.append("--search=\(search)") }
        arguments += ["--json", PullRequest.fields]
        return GitHubCommand(arguments, in: location)
    }

    public static func viewPullRequest(
        _ pullRequest: PullRequestSelector, in location: RepositoryLocation
    ) -> GitHubCommand {
        GitHubCommand(["pr", "view", pullRequest.argument, "--json", PullRequest.fields], in: location)
    }

    public static func checks(_ pullRequest: PullRequestSelector, in location: RepositoryLocation) -> GitHubCommand {
        GitHubCommand(["pr", "checks", pullRequest.argument, "--json", PullRequestCheck.fields], in: location)
    }

    /// Opens the pull request in the browser gh is configured with.
    public static func openInBrowser(
        _ pullRequest: PullRequestSelector, in location: RepositoryLocation
    ) -> GitHubCommand {
        GitHubCommand(["pr", "view", pullRequest.argument, "--web"], in: location)
    }
}

// MARK: - Changes

extension GitHubCommand {
    /// The body goes through stdin, so its length and content don't matter. gh prints the new pull
    /// request's URL.
    public static func createPullRequest(_ pullRequest: NewPullRequest, in directory: URL) -> GitHubCommand {
        var arguments = ["pr", "create", "--title=\(pullRequest.title)", "--body-file=-", "--head=\(pullRequest.head)"]
        if let base = pullRequest.base { arguments.append("--base=\(base)") }
        if pullRequest.isDraft { arguments.append("--draft") }
        return GitHubCommand(
            arguments, in: .directory(directory), input: Data(pullRequest.body.utf8), isMutating: true,
            timeout: .seconds(120))
    }

    /// Changes the working tree of `directory`, so use a fresh worktree: gh refuses to switch over
    /// uncommitted changes, and git won't check the head branch out twice, so pass `localBranch`
    /// or `detach` when it may be checked out elsewhere.
    public static func checkout(
        _ pullRequest: PullRequestSelector, in directory: URL, localBranch: String? = nil, detach: Bool = false
    ) -> GitHubCommand {
        var arguments = ["pr", "checkout", pullRequest.argument]
        if let localBranch { arguments.append("--branch=\(localBranch)") }
        if detach { arguments.append("--detach") }
        return GitHubCommand(arguments, in: .directory(directory), isMutating: true, timeout: .seconds(300))
    }

    /// Pass the head commit the user saw as `matchHeadCommit`, so a push that lands in between
    /// isn't merged unseen; and a `.remote` location, so `deleteBranch` leaves local checkouts alone.
    public static func merge(
        _ pullRequest: PullRequestSelector, in location: RepositoryLocation, method: MergeMethod,
        deleteBranch: Bool = false, matchHeadCommit: String? = nil, admin: Bool = false
    ) -> GitHubCommand {
        var arguments = ["pr", "merge", pullRequest.argument, "--\(method.rawValue)"]
        if deleteBranch { arguments.append("--delete-branch") }
        if admin { arguments.append("--admin") }
        if let matchHeadCommit { arguments.append("--match-head-commit=\(matchHeadCommit)") }
        return GitHubCommand(arguments, in: location, isMutating: true, timeout: .seconds(120))
    }

    /// Closes without merging. The branch stays, so it can be reopened.
    public static func close(_ pullRequest: PullRequestSelector, in location: RepositoryLocation) -> GitHubCommand {
        GitHubCommand(["pr", "close", pullRequest.argument], in: location, isMutating: true)
    }

    public static func reopen(_ pullRequest: PullRequestSelector, in location: RepositoryLocation) -> GitHubCommand {
        GitHubCommand(["pr", "reopen", pullRequest.argument], in: location, isMutating: true)
    }

    /// A comment on the conversation. The body goes through stdin, so its length and content don't
    /// matter.
    public static func comment(
        _ body: String, on pullRequest: PullRequestSelector, in location: RepositoryLocation
    ) -> GitHubCommand {
        GitHubCommand(
            ["pr", "comment", pullRequest.argument, "--body-file=-"], in: location, input: Data(body.utf8),
            isMutating: true)
    }
}
