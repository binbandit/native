import Foundation

/// A pull request as one GitHub poll saw it: just what event detection compares between polls.
public nonisolated struct PullRequestSnapshot: Codable, Hashable, Sendable, Identifiable {
    public var url: URL
    public var repository: String
    public var number: Int
    public var title: String
    public var updatedAt: Date
    /// The user opened it.
    public var isAuthored: Bool
    /// The user's review is requested.
    public var isReviewRequested: Bool
    public var hasFailingChecks: Bool

    public init(
        url: URL, repository: String, number: Int, title: String, updatedAt: Date, isAuthored: Bool,
        isReviewRequested: Bool, hasFailingChecks: Bool
    ) {
        self.url = url
        self.repository = repository
        self.number = number
        self.title = title
        self.updatedAt = updatedAt
        self.isAuthored = isAuthored
        self.isReviewRequested = isReviewRequested
        self.hasFailingChecks = hasFailingChecks
    }

    public var id: URL { url }

    public var subject: String {
        "\(repository)#\(number) \(title)"
    }
}
