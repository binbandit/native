import Foundation

/// A `gh search prs` query for pull requests involving a user, across every repository they can see.
public struct PullRequestSearch: Sendable, Hashable {
    public enum Involvement: String, Sendable, Hashable, CaseIterable {
        /// Opened by the user.
        case author
        /// Waiting on the user's review, directly or through a team.
        case reviewRequested
        /// Assigned to the user.
        case assignee
    }

    public enum State: String, Sendable, Hashable {
        case open, closed
    }

    public var involvement: Involvement
    /// A login, or `@me` for whoever gh is signed in as.
    public var user: String
    public var state: State
    /// `owner/name` repositories to limit to; empty searches everywhere.
    public var repositories: [String]
    /// Search keywords and qualifiers, e.g. `label:bug`.
    public var keywords: String?
    /// GitHub's search budget is 30 requests a minute, whatever the limit.
    public var limit: Int

    public init(
        _ involvement: Involvement, user: String = "@me", state: State = .open, repositories: [String] = [],
        keywords: String? = nil, limit: Int = 50
    ) {
        self.involvement = involvement
        self.user = user
        self.state = state
        self.repositories = repositories
        self.keywords = keywords
        self.limit = limit
    }
}
