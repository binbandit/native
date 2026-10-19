import Foundation

/// A merged pull request whose head was one of the user's local branches, for cleaning up branches
/// whose work landed through a squash or rebase merge (which leaves no trace in git's history).
public struct MergedPullRequest: Sendable, Hashable, Decodable {
    public var number: Int
    public var url: URL
    public var headRefName: String
    /// The head commit when it merged.
    public var headRefOid: String
    /// The branch it was merged into.
    public var baseRefName: String
    public var mergedAt: Date?

    public init(
        number: Int, url: URL, headRefName: String, headRefOid: String, baseRefName: String, mergedAt: Date? = nil
    ) {
        self.number = number
        self.url = url
        self.headRefName = headRefName
        self.headRefOid = headRefOid
        self.baseRefName = baseRefName
        self.mergedAt = mergedAt
    }

    /// A local branch to look up merged pull requests for.
    public struct Query: Sendable, Hashable {
        /// The local branch, which the results are keyed by.
        public var branch: String
        /// Its name on the remote, which a pull request's head is.
        public var head: String
        /// The pull request a task was opened for, looked up as well (its head may be a fork's
        /// branch with another name).
        public var pullRequest: URL?

        public init(branch: String, head: String, pullRequest: URL? = nil) {
            self.branch = branch
            self.head = head
            self.pullRequest = pullRequest
        }
    }
}
