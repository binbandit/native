import Foundation

/// A branch's pull requests, as a task's badge shows them: the one that matters now, and the others
/// the branch has had (a branch reused after its first pull request merged, say).
public struct BranchPullRequests: Sendable, Hashable {
    /// The newest open one, else the newest.
    public var current: PullRequest
    /// The rest, newest first.
    public var others: [PullRequest]

    /// `nil` when there are none.
    public init?(_ candidates: [PullRequest]) {
        let newestFirst = candidates.sorted { $0.createdAt > $1.createdAt }
        guard let current = newestFirst.first(where: { $0.state == .open }) ?? newestFirst.first else { return nil }
        self.current = current
        others = newestFirst.filter { $0.url != current.url }
    }

    /// Whether every other one was opened before the current one, so "and 2 earlier" is true. An
    /// open one wins over a newer closed one, which this is false for.
    public var othersAreEarlier: Bool {
        others.allSatisfy { $0.createdAt < current.createdAt }
    }
}
