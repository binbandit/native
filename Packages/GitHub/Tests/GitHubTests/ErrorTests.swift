import Testing

@testable import GitHub

/// Stderr as gh 2.102 printed it for each situation (captured with an empty `GH_CONFIG_DIR`, an
/// unresolvable host, and folders without a GitHub remote).
struct ErrorTests {
    @Test func notLoggedIn() {
        let stderr = """
            To get started with GitHub CLI, please run:  gh auth login
            Alternatively, populate the GH_TOKEN environment variable with a GitHub API authentication token.
            """
        #expect(GitHubError.classify(exitCode: 4, stderr: stderr) == .notAuthenticated(stderr))
    }

    @Test func rejectedToken() {
        let stderr = "HTTP 401: Bad credentials (https://api.github.com/user)\nTry authenticating with:  gh auth login"
        #expect(GitHubError.classify(exitCode: 1, stderr: stderr) == .notAuthenticated(stderr))
    }

    @Test func offline() {
        let stderr = "error connecting to api.github.com\ncheck your internet connection or https://githubstatus.com"
        #expect(GitHubError.classify(exitCode: 1, stderr: stderr) == .offline(stderr))
        let proxy =
            #"Get "https://api.github.com/user": proxyconnect tcp: dial tcp 127.0.0.1:9: connect: connection refused"#
        #expect(GitHubError.classify(exitCode: 1, stderr: proxy) == .offline(proxy))
    }

    @Test func rateLimited() {
        let primary = "GraphQL: API rate limit already exceeded for user ID 6337115."
        #expect(GitHubError.classify(exitCode: 1, stderr: primary) == .rateLimited(primary))
        let secondary =
            "HTTP 403: You have exceeded a secondary rate limit. Please wait a few minutes before you try again."
        #expect(GitHubError.classify(exitCode: 1, stderr: secondary) == .rateLimited(secondary))
    }

    @Test func notARepository() {
        let notGit = "failed to run git: fatal: not a git repository (or any of the parent directories): .git"
        #expect(GitHubError.classify(exitCode: 1, stderr: notGit) == .notARepository(notGit))
        #expect(
            GitHubError.classify(exitCode: 1, stderr: "no git remotes found") == .notARepository("no git remotes found")
        )
        // Ends by suggesting `gh auth login`, but it's about the remote, not the login.
        let otherHost =
            "none of the git remotes configured for this repository point to a known GitHub host. To tell gh about a new GitHub host, please use `gh auth login`"
        #expect(GitHubError.classify(exitCode: 1, stderr: otherHost) == .notARepository(otherHost))
    }

    @Test func notFound() {
        let branch = #"no pull requests found for branch "nonexistent""#
        #expect(GitHubError.classify(exitCode: 1, stderr: branch) == .notFound(branch))
        let number = "GraphQL: Could not resolve to a PullRequest with the number of 99999. (repository.pullRequest)"
        #expect(GitHubError.classify(exitCode: 1, stderr: number) == .notFound(number))
    }

    @Test func anythingElseKeepsGhsMessage() {
        let error = GitHubError.classify(
            exitCode: 1, stderr: "  a pull request for branch \"x\" into branch \"main\" already exists\n")
        #expect(error == .failed(exitCode: 1, #"a pull request for branch "x" into branch "main" already exists"#))
        #expect(error.stderr == #"a pull request for branch "x" into branch "main" already exists"#)
        #expect(error.isTransient)
    }

    @Test func onlyTransientFailuresAreRetried() {
        #expect(GitHubError.offline("").isTransient)
        #expect(GitHubError.rateLimited("").isTransient)
        #expect(!GitHubError.notAuthenticated("").isTransient)
        #expect(!GitHubError.notInstalled.isTransient)
    }
}
