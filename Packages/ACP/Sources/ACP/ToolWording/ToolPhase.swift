/// Where a call is in its lifecycle, as a client shows it.
public enum ToolPhase: Hashable, Sendable {
    /// `cancelled` is a call a stop cut short; `rejected` one the user or a rule refused, so it never
    /// ran (`ToolCallState.wasRefused`); `interrupted` one a crash cut off; `unreported` one whose turn
    /// ended without the agent saying how it went.
    case running, awaitingApproval, completed, failed, cancelled, rejected, interrupted, unreported

    public init(_ call: ToolCallState) {
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

    /// The word a row ends with when the call didn't simply succeed; nil when it did or still runs.
    /// A failed command that exited says how ("Exit 1").
    public func outcome(exitCode: Int?) -> String? {
        switch self {
        case .running, .completed: nil
        case .awaitingApproval: "Approval required"
        case .failed: exitCode.flatMap { $0 > 0 ? "Exit \($0)" : nil } ?? "Failed"
        case .cancelled: "Stopped"
        case .rejected: "Rejected"
        case .interrupted: "Interrupted"
        case .unreported: "No result"
        }
    }
}
