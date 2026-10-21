import ACP

/// Where a call is in its lifecycle, as the row shows it.
enum ToolPhase: Equatable {
    /// `cancelled` is a call a stop cut short; `rejected` one the user or a rule refused, so it never
    /// ran (`ToolCallState.wasRefused`); `interrupted` one a crash cut off; `unreported` one whose turn
    /// ended without the agent saying how it went.
    case running, awaitingApproval, completed, failed, cancelled, rejected, interrupted, unreported

    init(_ call: ToolCallState) {
        if call.permission != nil {
            self = .awaitingApproval
            return
        }
        // Claude Code leaves calls `pending` while they run, so both open states read as running.
        self =
            switch call.status {
            case .pending, .inProgress: .running
            case .completed: .completed
            case .failed: call.wasRefused ? .rejected : .failed
            case .cancelled: .cancelled
            case .interrupted: .interrupted
            case .unreported: .unreported
            }
    }
}
