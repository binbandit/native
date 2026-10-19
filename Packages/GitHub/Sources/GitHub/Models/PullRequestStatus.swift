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
    /// Queued or set to auto-merge, when it is.
    public var mergeState: PullRequestMergeState?

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
              \(PullRequestMergeState.fields)
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

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        headRefName = try container.decode(String.self, forKey: .headRefName)
        baseRefName = try container.decode(String.self, forKey: .baseRefName)
        reviewDecision = try container.decodeEnum(PullRequest.ReviewDecision.self, forKey: .reviewDecision)
        mergeable = try container.decodeEnum(PullRequest.Mergeable.self, forKey: .mergeable)
        additions = try container.decodeIfPresent(Int.self, forKey: .additions) ?? 0
        deletions = try container.decodeIfPresent(Int.self, forKey: .deletions) ?? 0
        checks = try container.decodeIfPresent(CheckRollup.LastCommit.self, forKey: .commits)?.rollup?.summary
        mergeState = try PullRequestMergeState.Payload(from: decoder).state
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
