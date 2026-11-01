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
    /// The context each participant was given, oldest first.
    public var transfers: [TaskHistoryTransfer]

    public init(
        id: TaskHistoryID, head: Int, participants: [TaskHistoryParticipant], current: Int,
        transfers: [TaskHistoryTransfer] = []
    ) {
        self.id = id
        self.head = head
        self.participants = participants
        self.current = current
        self.transfers = transfers
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

extension HostProtocol.Method {
    /// Client → host: a change of agent committed, so the new agent session joins the task's history
    /// (`JoinHistoryParams` → `TaskHistorySummary`). The client's handoff, which goes with the new
    /// session's next message, is recorded as a `client` transfer of what it hadn't seen.
    public static let joinHistory = "_native/history/join"
    /// Client → host: what a session's agent hasn't seen of its task (`SessionParams` →
    /// `TaskHistoryMissing`), for the context a return to it needs.
    public static let missingHistory = "_native/history/missing"
}

public struct JoinHistoryParams: Codable, Hashable, Sendable {
    /// The session joining: the agent session the task continues with.
    public var sessionID: HostSessionID
    /// The conversation it continues from, by its agent session, which may have closed since.
    public var sourceAgentID: String
    public var sourceAgentSessionID: SessionID
    /// The items of the task's history the client's handoff conveyed, from its receipt. Only these
    /// count as seen; empty when the client can't say.
    public var conveyed: [ClosedRange<Int>]
    /// The handoff's receipt, kept with the transfer for audit.
    public var receipt: JSONValue?

    public init(
        sessionID: HostSessionID, sourceAgentID: String, sourceAgentSessionID: SessionID,
        conveyed: [ClosedRange<Int>] = [], receipt: JSONValue? = nil
    ) {
        self.sessionID = sessionID
        self.sourceAgentID = sourceAgentID
        self.sourceAgentSessionID = sourceAgentSessionID
        self.conveyed = conveyed
        self.receipt = receipt
    }
}

/// What a session's agent hasn't seen of its task.
public struct TaskHistoryMissing: Codable, Hashable, Sendable {
    /// The session's watermark: it has everything up to here.
    public var seen: Int
    public var head: Int
    /// The newest 500 it hasn't seen, oldest first.
    public var items: [TaskHistoryItem]
    /// How many older ones were left out of `items`.
    public var omitted: Int

    public init(seen: Int, head: Int, items: [TaskHistoryItem], omitted: Int) {
        self.seen = seen
        self.head = head
        self.items = items
        self.omitted = omitted
    }
}
