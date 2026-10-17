import Foundation

/// One step's progress in a run.
nonisolated struct WorkflowStepRun: Codable, Hashable, Sendable, Identifiable {
    let step: WorkflowStep
    var status: WorkflowStepStatus = .waiting
    var assignment: WorkflowAssignment
    /// The prompt as rendered for this run; set once the step can run (and at its gate, where the
    /// user can edit it).
    var prompt: String?
    /// The session the step runs in (`SessionContext.clientID`).
    var task: UUID?
    /// What the step hands to the steps after it: its final reply without the goal status line, or
    /// for a pull request step, the pull request's URL.
    var output: String?
    /// The latest reply while the step works, for the run view.
    var latestReply: String?
    /// For goal steps, the loop driving the task.
    var goal: GoalLoop?
    /// Turns the task has taken for this step.
    var turns = 0
    /// The task session's running cost, as last reported.
    var sessionCost: Double?
    /// The session's cost when the step began, for a step that continues an earlier step's task.
    var costBaseline: Double?
    var startedAt: Date?
    var endedAt: Date?
    /// When the step started waiting on the user, so the oldest request can answer the shortcuts.
    var waitingSince: Date?

    init(step: WorkflowStep, assignment: WorkflowAssignment) {
        self.step = step
        self.assignment = assignment
    }

    var id: String {
        step.id
    }

    var cost: Double? {
        sessionCost.map { max(0, $0 - (costBaseline ?? 0)) }
    }

    /// Whether the user has something to answer here.
    var needsUser: Bool {
        switch status {
        case .awaitingApproval, .blocked: true
        default: false
        }
    }
}
