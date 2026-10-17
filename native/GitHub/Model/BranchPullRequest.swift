import Foundation
import GitHub

/// What a lookup found for a branch.
struct BranchPullRequest: Hashable, Sendable {
    /// `nil` when the branch has no pull request, or the folder isn't on GitHub.
    var pullRequest: PullRequestSummary?
    var fetchedAt: Date
}
