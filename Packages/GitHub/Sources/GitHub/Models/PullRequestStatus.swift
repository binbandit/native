import Foundation

/// What search leaves out, fetched for up to 100 pull requests with one GraphQL query: branches,
/// review decision, mergeability, size and the CI rollup with per-state counts.
public struct PullRequestStatus: Sendable, Hashable, Decodable {
    public var id: String
    public var headRefName: String
    public var baseRefName: String
    public var reviewDecision: PullRequest.ReviewDecision?
    public var mergeable: PullRequest.Mergeable?
    public var additions: Int
    public var deletions: Int
    /// `nil` when the head commit has no checks.
    public var checks: CheckSummary?

    static let query = """
        query($ids: [ID!]!) {
          nodes(ids: $ids) {
            ... on PullRequest {
              id
              headRefName
              baseRefName
              reviewDecision
              mergeable
              additions
              deletions
              commits(last: 1) {
                nodes {
                  commit {
                    statusCheckRollup {
                      state
                      contexts {
                        checkRunCountsByState { state count }
                        statusContextCountsByState { state count }
                      }
                    }
                  }
                }
              }
            }
          }
        }
        """

    private enum CodingKeys: String, CodingKey {
        case id, headRefName, baseRefName, reviewDecision, mergeable, additions, deletions, commits
    }

    private struct Commits: Decodable {
        struct Node: Decodable {
            struct Commit: Decodable {
                var statusCheckRollup: Rollup?
            }

            var commit: Commit
        }

        var nodes: [Node]
    }

    private struct Rollup: Decodable {
        struct Contexts: Decodable {
            var checkRunCountsByState: [Tally]?
            var statusContextCountsByState: [Tally]?
        }

        struct Tally: Decodable {
            var state: String
            var count: Int
        }

        var state: String
        var contexts: Contexts?
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        headRefName = try container.decode(String.self, forKey: .headRefName)
        baseRefName = try container.decode(String.self, forKey: .baseRefName)
        reviewDecision = try container.decodeEnum(PullRequest.ReviewDecision.self, forKey: .reviewDecision)
        mergeable = try container.decodeEnum(PullRequest.Mergeable.self, forKey: .mergeable)
        additions = try container.decodeIfPresent(Int.self, forKey: .additions) ?? 0
        deletions = try container.decodeIfPresent(Int.self, forKey: .deletions) ?? 0
        let rollup = try container.decodeIfPresent(Commits.self, forKey: .commits)?.nodes.last?.commit.statusCheckRollup
        checks = rollup.map(Self.summary)
    }

    /// GitHub's own rollup state (it knows about required checks that haven't reported), with
    /// counts from its per-state tallies.
    private static func summary(_ rollup: Rollup) -> CheckSummary {
        var counts = [CheckOutcome: Int]()
        let tallies =
            (rollup.contexts?.checkRunCountsByState ?? []) + (rollup.contexts?.statusContextCountsByState ?? [])
        for tally in tallies where tally.count > 0 {
            counts[CheckOutcome(state: tally.state), default: 0] += tally.count
        }
        let state: CheckSummary.State =
            switch rollup.state.uppercased() {
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

    /// The GraphQL response around a batch of statuses.
    struct Response: Decodable {
        struct Payload: Decodable {
            var nodes: [Node?]
        }

        /// Ids that no longer resolve come back as `null`, and ids of other types as `{}`.
        struct Node: Decodable {
            var status: PullRequestStatus?

            init(from decoder: any Decoder) throws {
                status = try? PullRequestStatus(from: decoder)
            }
        }

        var data: Payload
    }
}
