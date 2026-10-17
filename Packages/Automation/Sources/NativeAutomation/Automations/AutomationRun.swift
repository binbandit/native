import Foundation

/// One run of an automation, kept in its history.
public nonisolated struct AutomationRun: Codable, Hashable, Sendable, Identifiable {
    public let id: UUID
    public let automation: Automation.ID
    public let reason: AutomationRunReason
    public let startedAt: Date
    public var endedAt: Date?
    public var status: AutomationRunStatus
    /// The workflow run doing the work.
    public var workflowRun: WorkflowRun.ID?
    /// The folder it works in: a fresh worktree, or the project.
    public var workspace: URL?
    /// A line about how it went: its result, or what went wrong.
    public var summary: String?

    public init(id: UUID = UUID(), automation: Automation.ID, reason: AutomationRunReason, startedAt: Date, status: AutomationRunStatus = .preparing) {
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
