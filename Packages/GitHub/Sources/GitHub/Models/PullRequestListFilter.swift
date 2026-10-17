import Foundation

/// Which pull requests `gh pr list` returns for one repository.
public struct PullRequestListFilter: Sendable, Hashable {
    public enum State: String, Sendable, Hashable {
        case open, closed, merged, all
    }

    public var state: State
    /// A login, or `@me`.
    public var author: String?
    /// Only pull requests whose head is this branch.
    public var head: String?
    /// GitHub search syntax, e.g. `review-requested:@me`.
    public var search: String?
    public var limit: Int

    public init(
        state: State = .open, author: String? = nil, head: String? = nil, search: String? = nil, limit: Int = 30
    ) {
        self.state = state
        self.author = author
        self.head = head
        self.search = search
        self.limit = limit
    }
}
