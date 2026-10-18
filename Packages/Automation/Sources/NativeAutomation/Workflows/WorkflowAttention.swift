/// What a change to a run means for the user, for sounds and notifications: it started waiting on
/// them, or it stopped short.
public nonisolated enum WorkflowAttention: Hashable, Sendable {
    /// A gate waits for approval, or a goal step for an answer.
    case needsUser
    /// A step stopped short and nothing is running: the user decides how to go on.
    case halted

    /// What a run's move from `previous` to `current` calls for; nil when the phase didn't change
    /// or the user needn't hear about it.
    public init?(from previous: WorkflowRunPhase?, to current: WorkflowRunPhase) {
        guard previous != current else { return nil }
        switch current {
        case .awaitingApproval, .blocked: self = .needsUser
        case .halted: self = .halted
        case .running, .paused, .succeeded, .cancelled: return nil
        }
    }
}
