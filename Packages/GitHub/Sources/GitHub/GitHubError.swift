import Foundation

/// Why a `gh` command failed. Cases that carry a `String` hold what gh printed to stderr, so the UI
/// can show gh's own explanation alongside its guidance.
public enum GitHubError: Error, Sendable, Hashable {
    /// No `gh` executable on the PATH of the environment we were given.
    case notInstalled
    /// gh has no usable login for the host (exit code 4, or a rejected token).
    case notAuthenticated(String)
    /// The primary or secondary rate limit was hit.
    case rateLimited(String)
    /// The host couldn't be reached.
    case offline(String)
    /// The folder isn't a git repository, or none of its remotes is a GitHub host gh knows.
    case notARepository(String)
    /// The pull request, branch or repository doesn't exist (or isn't visible to the user).
    case notFound(String)
    /// The account can see this but may not do it: merging without write access, approving one's
    /// own pull request, commenting on a locked conversation.
    case permissionDenied(String)
    /// gh didn't finish in time and was stopped.
    case timedOut
    /// The task waiting on gh was cancelled, and gh with it.
    case cancelled
    /// gh exited unsuccessfully for another reason.
    case failed(exitCode: Int32, String)
    /// gh succeeded but printed something we couldn't decode.
    case unexpectedOutput(String)

    /// What gh printed to stderr, when the failure came from gh itself.
    public var stderr: String? {
        switch self {
        case .notAuthenticated(let message), .rateLimited(let message), .offline(let message),
            .notARepository(let message), .notFound(let message), .failed(_, let message):
            message
        case .notInstalled, .timedOut, .cancelled, .unexpectedOutput:
            nil
        }
    }

    /// Whether trying again later could succeed without the user doing anything.
    public var isTransient: Bool {
        switch self {
        case .rateLimited, .offline, .timedOut, .failed: true
        case .notInstalled, .notAuthenticated, .notARepository, .notFound, .permissionDenied, .cancelled,
            .unexpectedOutput:
            false
        }
    }

    /// Classifies a failed run from its exit code and stderr. gh has no machine-readable error
    /// output, so this matches the messages gh and the GitHub API print, which have been stable for
    /// years; anything unrecognized keeps its message in `.failed`.
    static func classify(exitCode: Int32, stderr: String) -> GitHubError {
        let message = stderr.trimmingCharacters(in: .whitespacesAndNewlines)
        let text = message.lowercased()
        func mentions(_ needles: String...) -> Bool {
            needles.contains { text.contains($0) }
        }

        // First, since gh's "no GitHub remote" message ends by suggesting `gh auth login`.
        if mentions(
            "not a git repository", "no git remotes found", "none of the git remotes configured",
            "could not determine base repo", "could not determine current repository"
        ) {
            return .notARepository(message)
        }
        // gh exits with 4 when a command needs a login it doesn't have.
        if exitCode == 4
            || mentions("gh auth login", "bad credentials", "http 401", "authentication required", "token has expired")
        {
            return .notAuthenticated(message)
        }
        if mentions("rate limit", "http 429", "abuse detection") {
            return .rateLimited(message)
        }
        // After rate limits, which GitHub also reports as 403s.
        if mentions(
            "resource not accessible", "http 403", "must have push access", "must have admin rights",
            "must have write access", "can not approve your own", "can not request changes on your own",
            "doesn't have permission", "does not have permission", "not authorized", "is locked",
            "permission to merge"
        ) {
            return .permissionDenied(message)
        }
        if mentions(
            "error connecting to", "check your internet connection", "no such host", "dial tcp",
            "connection refused", "network is unreachable", "i/o timeout", "tls handshake timeout",
            "connection reset", "server misbehaving", "could not resolve host"
        ) {
            return .offline(message)
        }
        if mentions("could not resolve to a", "http 404", "no pull requests found") {
            return .notFound(message)
        }
        return .failed(exitCode: exitCode, message)
    }
}

extension GitHubError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .notInstalled: "GitHub CLI isn't installed."
        case .notAuthenticated: "GitHub CLI isn't signed in."
        case .rateLimited: "GitHub's rate limit was reached."
        case .offline: "GitHub couldn't be reached."
        case .notARepository: "This folder isn't a GitHub repository."
        case .notFound: "Not found on GitHub."
        case .permissionDenied(let message): Self.permissionSummary(message)
        case .timedOut: "GitHub CLI took too long to respond."
        case .cancelled: "Cancelled."
        case .failed(_, let message): message.isEmpty ? "GitHub CLI failed." : message
        case .unexpectedOutput: "GitHub CLI returned something unexpected."
        }
    }

    public var recoverySuggestion: String? {
        switch self {
        case .notInstalled: "Install it with `brew install gh`, or from cli.github.com."
        case .notAuthenticated: "Run `gh auth login` in a terminal, then refresh."
        case .rateLimited: "Native will try again once the limit resets."
        case .offline: "Check your connection; Native will try again."
        case .notARepository: "Open a folder whose git remote points at GitHub."
        case .permissionDenied: "Ask a maintainer of the repository, or do it on GitHub with an account that can."
        case .notFound, .timedOut, .cancelled, .failed, .unexpectedOutput: nil
        }
    }
}

extension GitHubError {
    /// GitHub's reasons say what was refused in its own words; these are the common ones, in plain
    /// language.
    fileprivate static func permissionSummary(_ message: String) -> String {
        let text = message.lowercased()
        if text.contains("approve your own") { return "You can't approve your own pull request." }
        if text.contains("request changes on your own") { return "You can't request changes on your own pull request." }
        if text.contains("is locked") { return "The conversation is locked." }
        if text.contains("merge") { return "Your account can't merge this pull request." }
        return "Your account doesn't have permission to do that here."
    }
}
