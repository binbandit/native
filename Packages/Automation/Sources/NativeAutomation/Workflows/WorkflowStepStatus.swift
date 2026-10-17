import Foundation

/// Where one step of a run stands.
public nonisolated enum WorkflowStepStatus: Codable, Hashable, Sendable {
    /// Waiting for the steps before it.
    case waiting
    /// Its gate is waiting for the user.
    case awaitingApproval
    /// Its task is being created.
    case starting
    case running
    /// Held because the run is paused: its next prompt goes out when the run resumes.
    case paused
    /// A goal step whose agent needs the user; a reply picks it back up.
    case blocked(String)
    /// Out of budget, or stopped by a provider limit.
    case limited(String)
    case failed(String)
    case cancelled
    /// It was working when Native (the host) quit. Nothing resumes on its own; the user resumes it
    /// in the same task, or stops.
    case interrupted
    case succeeded
    case skipped

    /// Done for the run's purposes: steps after it can start.
    public var isFinished: Bool {
        switch self {
        case .succeeded, .skipped: true
        default: false
        }
    }

    /// Working without the user.
    public var isActive: Bool {
        switch self {
        case .starting, .running: true
        default: false
        }
    }

    /// Stopped short, waiting for the user to resume, retry, accept or skip it.
    public var isStopped: Bool {
        switch self {
        case .blocked, .limited, .failed, .cancelled, .interrupted: true
        default: false
        }
    }

    public var reason: String? {
        switch self {
        case .blocked(let reason), .limited(let reason), .failed(let reason): reason
        case .interrupted: "Native quit while this step was working."
        default: nil
        }
    }

    public var label: String {
        switch self {
        case .waiting: "Waiting"
        case .awaitingApproval: "Needs approval"
        case .starting: "Starting"
        case .running: "Working"
        case .paused: "Paused"
        case .blocked: "Blocked"
        case .limited: "Limited"
        case .failed: "Failed"
        case .cancelled: "Stopped"
        case .interrupted: "Interrupted"
        case .succeeded: "Done"
        case .skipped: "Skipped"
        }
    }
}
