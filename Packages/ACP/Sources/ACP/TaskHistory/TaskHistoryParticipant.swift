import Foundation

/// An agent session that took part in a task, numbered in the order it joined.
public struct TaskHistoryParticipant: Hashable, Sendable, Codable, Identifiable {
    /// 1 for the session the task started on, then one more for each agent session that joins.
    public var ordinal: Int
    public var agentID: String
    public var agentSessionID: SessionID
    /// The model it last ran with, as its agent names the value.
    public var model: String?
    public var joinedAt: Date
    /// Every item up to this `seq` is in the agent session's context: it produced the item, received
    /// it as a prompt, or was given it in a handoff.
    public var seen: Int
    /// Its agent deleted the session, so it can't be reopened. What it did stays in the history.
    public var isGone: Bool

    public init(
        ordinal: Int, agentID: String, agentSessionID: SessionID, model: String? = nil, joinedAt: Date = .now,
        seen: Int = 0, isGone: Bool = false
    ) {
        self.ordinal = ordinal
        self.agentID = agentID
        self.agentSessionID = agentSessionID
        self.model = model
        self.joinedAt = joinedAt
        self.seen = seen
        self.isGone = isGone
    }

    public var id: Int { ordinal }
}
