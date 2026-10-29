import Foundation

/// A commit as one line of a list: what a force-push would drop, for instance.
public struct CommitSummary: Hashable, Sendable {
    public let hash: String
    public let subject: String
    public let date: Date

    public init(hash: String, subject: String, date: Date) {
        self.hash = hash
        self.subject = subject
        self.date = date
    }
}
