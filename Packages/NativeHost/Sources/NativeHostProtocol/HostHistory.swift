import ACP
import Foundation

// One task history (docs/decisions/2026-11-01-one-task-history.md): the host keeps one
// provider-neutral record per task, whichever agent sessions take part in it. A session's history
// is found through its agent session, so it outlives the host session that opened it.
extension HostProtocol.Method {
    /// Client → host: the history of a session's task, with every agent session that took part
    /// (`SessionParams` → `TaskHistorySummary`).
    public static let historySummary = "_native/history/summary"
    /// Client → host: items of a session's task history, oldest first (`ReadHistoryParams` →
    /// `[TaskHistoryItem]`).
    public static let readHistory = "_native/history/read"
}

/// A task's history as one session sees it.
public struct TaskHistorySummary: Codable, Hashable, Sendable {
    public var id: TaskHistoryID
    /// The newest item's `seq`; 0 before anything is recorded.
    public var head: Int
    /// In the order they joined.
    public var participants: [TaskHistoryParticipant]
    /// The asking session's own participant ordinal.
    public var current: Int

    public init(id: TaskHistoryID, head: Int, participants: [TaskHistoryParticipant], current: Int) {
        self.id = id
        self.head = head
        self.participants = participants
        self.current = current
    }
}

public struct ReadHistoryParams: Codable, Hashable, Sendable {
    public var sessionID: HostSessionID
    /// Items after this `seq`.
    public var after: Int
    /// Up to and including this `seq`; nil reads to the newest.
    public var through: Int?
    /// At most this many; the host caps it at 500.
    public var limit: Int

    public init(sessionID: HostSessionID, after: Int = 0, through: Int? = nil, limit: Int = 500) {
        self.sessionID = sessionID
        self.after = after
        self.through = through
        self.limit = limit
    }
}
