import Foundation

/// What the sidebar's filters and sorts need to know about one task, worked out by the app from
/// its session, its checkout and its pull request.
public struct TaskFacts: Hashable, Sendable {
    /// Where the task stands, most urgent first: the order the Status sort uses.
    public enum Activity: Int, Comparable, Sendable, CaseIterable {
        /// Asking the user something: a permission, a question, a plan to review.
        case needsYou
        /// Starting, or working on a turn.
        case running
        /// The last turn or the agent failed.
        case failed
        /// The last turn finished.
        case done
        /// Nothing has happened in this run, or the last turn was stopped.
        case idle

        public static func < (lhs: Self, rhs: Self) -> Bool {
            lhs.rawValue < rhs.rawValue
        }
    }

    public var activity: Activity
    public var isUnread: Bool
    /// The agent's id, as its plugin names it ("codex").
    public var agent: String
    public var hasUncommittedChanges: Bool
    public var hasPullRequest: Bool
    public var isArchived: Bool
    public var title: String
    public var lastActivity: Date?

    public init(
        activity: Activity = .idle, isUnread: Bool = false, agent: String, hasUncommittedChanges: Bool = false,
        hasPullRequest: Bool = false, isArchived: Bool = false, title: String, lastActivity: Date? = nil
    ) {
        self.activity = activity
        self.isUnread = isUnread
        self.agent = agent
        self.hasUncommittedChanges = hasUncommittedChanges
        self.hasPullRequest = hasPullRequest
        self.isArchived = isArchived
        self.title = title
        self.lastActivity = lastActivity
    }
}
