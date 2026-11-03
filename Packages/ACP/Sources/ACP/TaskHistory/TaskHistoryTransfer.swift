import Foundation

/// Context a participant was given about items it hadn't seen: a new agent session's handoff, a
/// return with what happened meanwhile, or (later) a fork's merge-back. It keeps the range it
/// considered apart from the items it conveyed: a budget or an excerpt can convey fewer, and only
/// conveyed items count as seen.
public struct TaskHistoryTransfer: Hashable, Sendable, Codable, Identifiable {
    public enum Strategy: String, Hashable, Sendable, Codable {
        /// Everything a new agent session needs from the task so far.
        case full
        /// What a returning agent session missed.
        case delta
        /// A handoff a client assembled and sent itself, as the change-agent flow does.
        case client
        case unknown

        public init(from decoder: any Decoder) throws {
            self = Self(rawValue: try decoder.singleValueContainer().decode(String.self)) ?? .unknown
        }
    }

    public enum State: String, Hashable, Sendable, Codable {
        /// Waiting for the target's next message.
        case prepared
        /// It went with a message; the agent hasn't answered yet.
        case sent
        /// The agent answered the message it went with, so it has the context.
        case delivered
        /// Undone before it was sent.
        case superseded
        case unknown

        public init(from decoder: any Decoder) throws {
            self = Self(rawValue: try decoder.singleValueContainer().decode(String.self)) ?? .unknown
        }
    }

    public var id: UUID
    /// Where its items come from: this history, or another one (a fork's, for merge-back).
    public var sourceHistory: TaskHistoryID
    /// The participant it's for.
    public var target: Int
    /// The items it considered: after `from`, up to and including `through`.
    public var from: Int
    public var through: Int
    /// The items it actually conveyed, as `seq` ranges.
    public var conveyed: [ClosedRange<Int>]
    public var strategy: Strategy
    public var state: State
    /// The message it went with.
    public var requestID: UUID?
    public var createdAt: Date

    /// The marker the context a host renders for this transfer goes with, so a transcript can show
    /// what it covered where it went.
    public var markerID: String { "task-history:\(id.uuidString)" }

    /// Whether a transcript marker is one a host transfer goes with, rather than a mode's.
    public static func isMarkerID(_ id: String) -> Bool { id.hasPrefix("task-history:") }

    public init(
        id: UUID = UUID(), sourceHistory: TaskHistoryID, target: Int, from: Int, through: Int,
        conveyed: [ClosedRange<Int>], strategy: Strategy, state: State = .prepared, requestID: UUID? = nil,
        createdAt: Date = .now
    ) {
        self.id = id
        self.sourceHistory = sourceHistory
        self.target = target
        self.from = from
        self.through = through
        self.conveyed = conveyed
        self.strategy = strategy
        self.state = state
        self.requestID = requestID
        self.createdAt = createdAt
    }
}
