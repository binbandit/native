import Foundation

/// A step task's session as the runner reads it: when a turn ends, and while the run view shows it.
nonisolated struct WorkflowTaskReport: Hashable, Sendable {
    /// What the agent said to close its latest turn.
    var reply: String?
    /// The session's running cost, when its agent reports one.
    var cost: Double?
    /// A tool call in the task is waiting for the user's permission.
    var needsApproval: Bool

    init(reply: String?, cost: Double?, needsApproval: Bool = false) {
        self.reply = reply
        self.cost = cost
        self.needsApproval = needsApproval
    }
}
