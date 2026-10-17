import Foundation

/// One run of an automation, kept in its history.
nonisolated struct AutomationRun: Codable, Hashable, Sendable, Identifiable {
    let id: UUID
    let automation: Automation.ID
    let reason: AutomationRunReason
    let startedAt: Date
    var endedAt: Date?
    var status: AutomationRunStatus
    /// The workflow run doing the work.
    var workflowRun: WorkflowRun.ID?
    /// The folder it works in: a fresh worktree, or the project.
    var workspace: URL?
    /// A line about how it went: its result, or what went wrong.
    var summary: String?

    init(id: UUID = UUID(), automation: Automation.ID, reason: AutomationRunReason, startedAt: Date, status: AutomationRunStatus = .preparing) {
        self.id = id
        self.automation = automation
        self.reason = reason
        self.startedAt = startedAt
        self.status = status
        if case .skipped = status {
            endedAt = startedAt
        }
    }
}
