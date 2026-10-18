import ACP

/// Where a call is in its lifecycle, as the row shows it.
enum ToolPhase: Equatable {
    case running, awaitingApproval, completed, failed, cancelled

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
            case .failed: .failed
            case .cancelled: .cancelled
            }
    }
}
