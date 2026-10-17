import Foundation

/// A step task's session as the runner reads it: when a turn ends, and while the run view shows it.
public nonisolated struct WorkflowTaskReport: Codable, Hashable, Sendable {
    /// What the agent said to close its latest turn.
    public var reply: String?
    /// The session's running cost, when its agent reports one.
    public var cost: Double?
    /// A tool call in the task is waiting for the user's permission.
    public var needsApproval: Bool

    public init(reply: String?, cost: Double?, needsApproval: Bool = false) {
        self.reply = reply
        self.cost = cost
        self.needsApproval = needsApproval
    }
}
