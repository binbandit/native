import Foundation

/// A commit's `statusCheckRollup` as GraphQL returns it: GitHub's overall state (which counts
/// required checks that haven't reported yet) and its per-state tallies.
struct CheckRollup: Decodable, Sendable {
    struct Contexts: Decodable, Sendable {
        var checkRunCountsByState: [Tally]?
        var statusContextCountsByState: [Tally]?
    }

    struct Tally: Decodable, Sendable {
        var state: String
        var count: Int
    }

    var state: String
    var contexts: Contexts?

    var summary: CheckSummary {
        var counts = [CheckOutcome: Int]()
        let tallies =
            (contexts?.checkRunCountsByState ?? []) + (contexts?.statusContextCountsByState ?? [])
        for tally in tallies where tally.count > 0 {
            counts[CheckOutcome(state: tally.state), default: 0] += tally.count
        }
        let state: CheckSummary.State =
            switch state.uppercased() {
            case "SUCCESS": .passing
            case "FAILURE", "ERROR": .failing
            default: .pending
            }
        return CheckSummary(
            state: state,
            passed: counts[.passed] ?? 0,
            failed: counts[.failed] ?? 0,
            pending: counts[.pending] ?? 0,
            skipped: counts[.skipped] ?? 0
        )
    }

    /// `commits(last: 1) { nodes { commit { oid statusCheckRollup { … } } } }`, the head commit's.
    struct LastCommit: Decodable, Sendable {
        struct Node: Decodable, Sendable {
            struct Commit: Decodable, Sendable {
                var oid: String?
                var statusCheckRollup: CheckRollup?
            }

            var commit: Commit
        }

        var nodes: [Node]

        var rollup: CheckRollup? {
            nodes.last?.commit.statusCheckRollup
        }
    }
}
