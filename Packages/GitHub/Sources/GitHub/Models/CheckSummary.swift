import Foundation

/// A pull request's CI at a glance: the overall state and how many checks landed where.
public struct CheckSummary: Sendable, Hashable {
    public enum State: String, Sendable, Hashable, CaseIterable {
        case passing
        case failing
        case pending
    }

    public var state: State
    public var passed: Int
    public var failed: Int
    public var pending: Int
    public var skipped: Int

    public init(state: State, passed: Int = 0, failed: Int = 0, pending: Int = 0, skipped: Int = 0) {
        self.state = state
        self.passed = passed
        self.failed = failed
        self.pending = pending
        self.skipped = skipped
    }

    public var total: Int {
        passed + failed + pending + skipped
    }

    /// Derives the state as GitHub's rollup does: any failure fails it, then anything unfinished
    /// keeps it pending. `nil` when there are no checks at all.
    public init?(outcomes: some Sequence<CheckOutcome>) {
        var counts = [CheckOutcome: Int]()
        for outcome in outcomes {
            counts[outcome, default: 0] += 1
        }
        guard !counts.isEmpty else { return nil }
        let failed = counts[.failed] ?? 0
        let pending = counts[.pending] ?? 0
        self.init(
            state: failed > 0 ? .failing : pending > 0 ? .pending : .passing,
            passed: counts[.passed] ?? 0,
            failed: failed,
            pending: pending,
            skipped: counts[.skipped] ?? 0
        )
    }
}
