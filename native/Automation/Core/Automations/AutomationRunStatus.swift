import Foundation

/// Where one run of an automation stands.
nonisolated enum AutomationRunStatus: Codable, Hashable, Sendable {
    /// Making its worktree and starting its workflow.
    case preparing
    case running
    /// A step is waiting on the user: an approval, a question.
    case needsYou
    case succeeded
    case failed(String)
    case cancelled
    /// Not started, and why: the previous run was still going, or the automation was paused.
    case skipped(String)

    var isOpen: Bool {
        switch self {
        case .preparing, .running, .needsYou: true
        default: false
        }
    }

    var label: String {
        switch self {
        case .preparing: "Starting"
        case .running: "Running"
        case .needsYou: "Needs you"
        case .succeeded: "Done"
        case .failed: "Failed"
        case .cancelled: "Stopped"
        case .skipped: "Skipped"
        }
    }

    /// The run's status from its workflow run's phase.
    init(phase: WorkflowRunPhase, reason: String?) {
        switch phase {
        case .running, .paused: self = .running
        case .awaitingApproval, .blocked: self = .needsYou
        case .halted: self = .failed(reason ?? "A step stopped short.")
        case .succeeded: self = .succeeded
        case .cancelled: self = .cancelled
        }
    }
}
