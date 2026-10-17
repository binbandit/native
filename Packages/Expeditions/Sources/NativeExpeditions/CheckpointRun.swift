import Foundation
import NativeAutomation

/// A leg's checkpoint: the reviewer's check of the leg once its assignments are done, and the
/// rounds of fixes it took.
public nonisolated struct CheckpointRun: Codable, Hashable, Sendable, Identifiable {
    public let leg: String
    public var status: WorkflowStepStatus = .waiting
    /// The reviewer's session, kept across rounds so it remembers what it asked for.
    public var task: UUID?
    /// Every verdict so far, oldest first.
    public var verdicts: [CheckpointVerdict] = []
    /// Fix rounds granted beyond the setting, by the user asking for another.
    public var extraRounds = 0
    public var latestReply: String?
    /// Replies without a verdict line in a row, so the reviewer is reminded once, then the user asked.
    public var unreadReplies = 0
    public var sessionCost: Double?
    public var startedAt: Date?
    public var endedAt: Date?
    public var waitingSince: Date?

    public init(leg: String) {
        self.leg = leg
    }

    public var id: String {
        leg
    }

    public var rounds: Int {
        verdicts.count
    }

    public var latestVerdict: CheckpointVerdict? {
        verdicts.last
    }
}
