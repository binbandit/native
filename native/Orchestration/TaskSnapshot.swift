import Foundation

/// A session at one moment, as another session sees it.
nonisolated struct TaskSnapshot: Hashable, Sendable {
    enum Status: String, Hashable, Sendable {
        case running
        /// A turn is in progress but blocked on the user answering a permission request.
        case needsApproval = "needs_approval"
        /// The latest turn ended, normally or stopped early by a limit or a refusal.
        case idle
        /// The latest turn errored, or the agent's process is gone.
        case failed
        case cancelled
    }

    var status: Status
    /// What the agent said to close its latest turn, so far; `SessionState.latestReply`.
    var reply: String?
    /// For needs_approval, what it's asking to do (`SessionState.awaitingApproval`). For failed, or
    /// an idle turn that stopped early, why.
    var detail: String?
}
