import Foundation
import GitHub

/// What a lookup found for a branch.
struct BranchPullRequest: Hashable, Sendable {
    /// `nil` when the branch has no pull request, or the folder isn't on GitHub.
    var pullRequest: PullRequestSummary?
    /// The branch's other pull requests, newest first.
    var others: [PullRequestSummary] = []
    /// Whether every other one came before `pullRequest`, so they read as "earlier".
    var othersAreEarlier = true
    /// When gh last answered.
    var loadedAt: Date
    /// When gh was last asked, answered or not: the cache's age.
    var fetchedAt: Date
    /// Why the last lookup failed, while an older answer shows.
    var failure: GitHubError?

    init(
        pullRequest: PullRequestSummary?, others: [PullRequestSummary] = [], othersAreEarlier: Bool = true,
        fetchedAt: Date
    ) {
        self.pullRequest = pullRequest
        self.others = others
        self.othersAreEarlier = othersAreEarlier
        loadedAt = fetchedAt
        self.fetchedAt = fetchedAt
    }

    init(_ found: BranchPullRequests?, fetchedAt: Date) {
        self.init(
            pullRequest: found.map { PullRequestSummary($0.current) },
            others: found?.others.map(PullRequestSummary.init) ?? [],
            othersAreEarlier: found?.othersAreEarlier ?? true,
            fetchedAt: fetchedAt)
    }
}
