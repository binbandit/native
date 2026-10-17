import Foundation

/// Where a goal stands. The same vocabulary as Claude's adapter goal extension
/// (`session_info_update._meta.jetbrains.air.goal`), so its snapshots map onto it one to one.
nonisolated enum GoalStatus: String, Codable, Hashable, Sendable, CaseIterable {
    /// Native keeps the agent working, turn after turn.
    case active
    /// Stopped by the user or by a turn that was cancelled or failed; resumable.
    case paused
    /// The agent said it can't go on without the user.
    case blocked
    /// The budget ran out, or the provider stopped the agent at one of its limits.
    case limited
    /// The agent reported the objective met.
    case complete

    var label: String {
        switch self {
        case .active: "Active"
        case .paused: "Paused"
        case .blocked: "Blocked"
        case .limited: "Limited"
        case .complete: "Complete"
        }
    }

    /// Whether the user can pick the goal back up.
    var isResumable: Bool {
        switch self {
        case .paused, .blocked, .limited: true
        case .active, .complete: false
        }
    }
}
