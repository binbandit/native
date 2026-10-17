import Foundation

/// How one check came out, folded the way GitHub's rollup folds them.
public enum CheckOutcome: String, Sendable, Hashable, CaseIterable {
    case passed
    /// Failed, errored, timed out, was cancelled, or needs action.
    case failed
    /// Queued, running, or required but not reported yet.
    case pending
    /// Skipped or neutral: neither blocks nor counts as a pass.
    case skipped

    /// Check-run conclusions and statuses, commit-status states and GraphQL's
    /// `checkRunCountsByState` keys share one vocabulary, so one mapping serves all of them.
    init(state: String) {
        switch state.uppercased() {
        case "SUCCESS":
            self = .passed
        case "FAILURE", "ERROR", "TIMED_OUT", "CANCELLED", "ACTION_REQUIRED", "STARTUP_FAILURE", "STALE":
            self = .failed
        case "NEUTRAL", "SKIPPED", "COMPLETED":
            self = .skipped
        default:
            // QUEUED, IN_PROGRESS, WAITING, PENDING, REQUESTED, EXPECTED, and states added later:
            // anything unsettled shouldn't read as done.
            self = .pending
        }
    }
}
