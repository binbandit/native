import Foundation

/// The user's open pull requests, by how they're involved. One pull request can appear in more
/// than one section (authored and assigned, say).
public struct PullRequestInbox: Sendable, Hashable {
    /// Opened by the user.
    public var authored: [PullRequestSummary]
    /// Waiting on the user's review.
    public var reviewRequested: [PullRequestSummary]
    /// Assigned to the user.
    public var assigned: [PullRequestSummary]
    public var fetchedAt: Date

    public init(
        authored: [PullRequestSummary] = [], reviewRequested: [PullRequestSummary] = [],
        assigned: [PullRequestSummary] = [], fetchedAt: Date = .now
    ) {
        self.authored = authored
        self.reviewRequested = reviewRequested
        self.assigned = assigned
        self.fetchedAt = fetchedAt
    }

    public subscript(involvement: PullRequestSearch.Involvement) -> [PullRequestSummary] {
        switch involvement {
        case .author: authored
        case .reviewRequested: reviewRequested
        case .assignee: assigned
        }
    }

    /// Every pull request once, most recently updated first.
    public var all: [PullRequestSummary] {
        var seen = Set<URL>()
        return (authored + reviewRequested + assigned)
            .filter { seen.insert($0.url).inserted }
            .sorted { $0.updatedAt > $1.updatedAt }
    }

    /// Combines inboxes from several hosts, keeping each section newest first.
    public static func merging(_ inboxes: [PullRequestInbox]) -> PullRequestInbox {
        func newestFirst(_ section: KeyPath<PullRequestInbox, [PullRequestSummary]>) -> [PullRequestSummary] {
            inboxes.flatMap { $0[keyPath: section] }.sorted { $0.updatedAt > $1.updatedAt }
        }
        return PullRequestInbox(
            authored: newestFirst(\.authored),
            reviewRequested: newestFirst(\.reviewRequested),
            assigned: newestFirst(\.assigned),
            fetchedAt: inboxes.map(\.fetchedAt).min() ?? .now
        )
    }
}
