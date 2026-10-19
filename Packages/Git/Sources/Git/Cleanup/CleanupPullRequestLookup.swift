import Foundation

/// What GitHub said about the branches `Repository.mergedCleanupPlan` asked about. The Git package
/// doesn't talk to GitHub; the caller answers its `Query`s however it can.
public enum CleanupPullRequestLookup: Sendable, Hashable {
    /// Each local branch's merged pull requests; a branch without one is absent.
    case found([String: [PullRequest]])
    /// GitHub couldn't be asked, and why ("gh isn't signed in").
    case unavailable(String)

    /// A branch to ask about: its merged pull requests, by the name it was pushed as, or the pull
    /// request Native checked it out for.
    public struct Query: Sendable, Hashable {
        /// The local branch.
        public var branch: String
        /// The branch's name on the remote, which a pull request's head is.
        public var head: String
        /// The pull request a task was opened for (the `nativePullRequest` branch note), if any.
        public var linkedPullRequest: URL?

        public init(branch: String, head: String, linkedPullRequest: URL? = nil) {
            self.branch = branch
            self.head = head
            self.linkedPullRequest = linkedPullRequest
        }
    }

    /// A merged pull request whose head was a branch being cleaned up.
    public struct PullRequest: Sendable, Hashable {
        public var number: Int
        public var url: URL?
        /// The head commit when it merged; the local branch must be at or behind it.
        public var headCommit: String
        /// The branch it was merged into.
        public var base: String

        public init(number: Int, url: URL? = nil, headCommit: String, base: String) {
            self.number = number
            self.url = url
            self.headCommit = headCommit
            self.base = base
        }
    }
}
