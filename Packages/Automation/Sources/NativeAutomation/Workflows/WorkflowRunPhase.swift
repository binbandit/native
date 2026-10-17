import Foundation

/// Where a run stands as a whole, for its header and its sidebar row.
public nonisolated enum WorkflowRunPhase: String, Codable, Hashable, Sendable {
    case running
    /// The user paused it; turns already running may still be finishing.
    case paused
    /// A gate is waiting for the user.
    case awaitingApproval
    /// A goal step needs the user's answer.
    case blocked
    /// Nothing is running and a step stopped short: the user decides how to go on.
    case halted
    case succeeded
    case cancelled

    public var label: String {
        switch self {
        case .running: "Running"
        case .paused: "Paused"
        case .awaitingApproval: "Needs approval"
        case .blocked: "Needs input"
        case .halted: "Stopped"
        case .succeeded: "Done"
        case .cancelled: "Cancelled"
        }
    }

    public var needsUser: Bool {
        switch self {
        case .awaitingApproval, .blocked, .halted: true
        case .running, .paused, .succeeded, .cancelled: false
        }
    }
}
