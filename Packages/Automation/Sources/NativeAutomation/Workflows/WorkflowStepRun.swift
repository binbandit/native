import Foundation

/// One step's progress in a run.
public nonisolated struct WorkflowStepRun: Codable, Hashable, Sendable, Identifiable {
    public let step: WorkflowStep
    public var status: WorkflowStepStatus = .waiting
    public var assignment: WorkflowAssignment
    /// The prompt as rendered for this run; set once the step can run (and at its gate, where the
    /// user can edit it).
    public var prompt: String?
    /// The session the step runs in (`SessionContext.clientID`).
    public var task: UUID?
    /// What the step hands to the steps after it: its final reply without the goal status line, or
    /// for a pull request step, the pull request's URL.
    public var output: String?
    /// The latest reply while the step works, for the run view.
    public var latestReply: String?
    /// For goal steps, the loop driving the task.
    public var goal: GoalLoop?
    /// Turns the task has taken for this step.
    public var turns = 0
    /// The task session's running cost, as last reported.
    public var sessionCost: Double?
    /// The session's cost when the step began, for a step that continues an earlier step's task.
    public var costBaseline: Double?
    public var startedAt: Date?
    public var endedAt: Date?
    /// When the step started waiting on the user, so the oldest request can answer the shortcuts.
    public var waitingSince: Date?

    public init(step: WorkflowStep, assignment: WorkflowAssignment) {
        self.step = step
        self.assignment = assignment
    }

    public var id: String {
        step.id
    }

    public var cost: Double? {
        sessionCost.map { max(0, $0 - (costBaseline ?? 0)) }
    }

    /// Whether the user has something to answer here.
    public var needsUser: Bool {
        switch status {
        case .awaitingApproval, .blocked: true
        default: false
        }
    }
}
