import Foundation

/// A pull request as one GitHub poll saw it: just what event detection compares between polls.
nonisolated struct PullRequestSnapshot: Codable, Hashable, Sendable, Identifiable {
    var url: URL
    var repository: String
    var number: Int
    var title: String
    var updatedAt: Date
    /// The user opened it.
    var isAuthored: Bool
    /// The user's review is requested.
    var isReviewRequested: Bool
    var hasFailingChecks: Bool

    var id: URL { url }

    var subject: String {
        "\(repository)#\(number) \(title)"
    }
}
