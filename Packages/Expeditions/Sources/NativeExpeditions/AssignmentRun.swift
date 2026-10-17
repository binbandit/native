import Foundation
import NativeAutomation

/// One assignment's progress. Its status is the workflow engine's step status, so assignments read
/// exactly like workflow steps everywhere Native shows one.
public nonisolated struct AssignmentRun: Codable, Hashable, Sendable, Identifiable {
    public var assignment: Route.Assignment
    public let leg: String
    public var status: WorkflowStepStatus = .waiting
    /// The session it runs in (`SessionContext.clientID`).
    public var task: UUID?
    /// Keeps the builder going until the work is done, within the assignment's iterations.
    public var goal: GoalLoop?
    /// The builder's final reply, without its status line: what it hands to the reviewer.
    public var report: String?
    public var latestReply: String?
    public var turns = 0
    public var sessionCost: Double?
    /// The session's cost when the assignment began, for a fix round in an earlier session.
    public var costBaseline: Double?
    public var startedAt: Date?
    public var endedAt: Date?
    /// When it started waiting on the user, so the oldest card answers the shortcuts.
    public var waitingSince: Date?
    /// Failed turns Native resumed on its own. One per assignment, so a crashing agent can't loop.
    public var automaticRecoveries = 0
    /// For a fix round a checkpoint asked for, which round it is; nil for work from the route.
    public let fixRound: Int?

    public init(assignment: Route.Assignment, leg: String, fixRound: Int? = nil) {
        self.assignment = assignment
        self.leg = leg
        self.fixRound = fixRound
    }

    public var id: String {
        assignment.id
    }

    public var cost: Double? {
        sessionCost.map { max(0, $0 - (costBaseline ?? 0)) }
    }

    /// A fix round from a checkpoint, rather than work from the route.
    public var isFix: Bool {
        fixRound != nil
    }
}
