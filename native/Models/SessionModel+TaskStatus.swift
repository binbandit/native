import ACP

extension SessionModel {
    /// Where the task stands, in the one vocabulary every surface uses (docs/product-quality.md):
    /// working, needs you (a question, an approval or a plan), finished, failed or stopped. The
    /// sidebar, Home, the status bar and the transcript's working line all read this, so a task
    /// waiting on the user never reads as working in one place and as needing you in another.
    ///
    /// What the task waits for wins over its phase: a turn blocked on an approval is still
    /// `.prompting`, but it's the user's move, not the agent's. Built only from properties the
    /// session mirrors, so reading it doesn't update with every streamed chunk.
    var taskStatus: TaskStatus {
        switch wait {
        case .input: return .needsInput
        case .permission: return .needsPermission
        case .planReview: return .needsPlanReview
        case nil: break
        }
        // A subagent said it's blocked on the user before its request reached this session.
        if needsApproval {
            return .needsPermission
        }
        // Native sends the prompt again on its own after a network blip, so the task isn't failed.
        if isRetryScheduled {
            return .working
        }
        switch phase {
        case .loading: return .starting
        case .prompting: return .working
        case .disconnected: return .failed
        case .idle:
            switch lastStopReason {
            case .endTurn, .maxTokens, .maxTurnRequests: return .done
            case .refusal, .error: return .failed
            case .cancelled: return .cancelled
            case .other, nil: return .idle
            }
        }
    }
}
