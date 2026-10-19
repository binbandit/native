import Foundation

// Getting a pull request into a local checkout: what checking it out needs to know, and cloning
// its repository when there's no checkout yet.
extension GitHubCommand {
    public static func pullRequestDetails(_ reference: PullRequestReference) -> GitHubCommand {
        GitHubCommand(
            ["pr", "view", String(reference.number), "--json", PullRequestDetails.fields],
            in: .remote(reference.ghHost.map { "\($0)/\(reference.repository)" } ?? reference.repository))
    }

    /// Clones with the user's own gh, so the protocol they chose in `gh auth login` (HTTPS or SSH)
    /// and their credentials apply. Creates `folder`, which must not exist or be empty. The folder
    /// is absolute, so it can't be read as a flag (after `--`, gh would pass it on to git as one).
    public static func clone(_ repository: RemoteRepository, to folder: URL) -> GitHubCommand {
        GitHubCommand(
            ["repo", "clone", repository.description, folder.standardizedFileURL.path(percentEncoded: false)],
            isMutating: true, timeout: .seconds(30 * 60))
    }
}

extension GitHubCLI {
    public func pullRequestDetails(_ reference: PullRequestReference) async throws(GitHubError) -> PullRequestDetails {
        try GitHubJSON.decode(PullRequestDetails.self, from: try await forPullRequest(reference).run(.pullRequestDetails(reference)))
    }

    public func clone(_ repository: RemoteRepository, to folder: URL) async throws(GitHubError) {
        _ = try await run(.clone(repository, to: folder))
    }
}
