import Foundation

/// A pull request with the detail `gh pr view` and `gh pr list` provide.
public struct PullRequest: Sendable, Hashable, Decodable, Identifiable {
    public var number: Int
    public var title: String
    public var body: String?
    public var url: URL
    public var state: State
    public var isDraft: Bool
    public var author: GitHubActor?
    public var headRefName: String
    public var baseRefName: String
    /// The head commit, to pass as `matchHeadCommit` when merging.
    public var headRefOid: String?
    public var reviewDecision: ReviewDecision?
    /// Every check run and commit status on the head commit.
    public var statusCheckRollup: [StatusCheck]
    /// Each reviewer's latest review.
    public var latestReviews: [PullRequestReview]
    public var mergeable: Mergeable?
    public var mergeStatus: MergeStatus?
    public var labels: [PullRequestLabel]
    public var additions: Int?
    public var deletions: Int?
    public var createdAt: Date
    public var updatedAt: Date
    public var mergedAt: Date?
    public var closedAt: Date?
    /// Whether the head lives in a fork.
    public var isCrossRepository: Bool

    public var id: URL { url }

    /// `owner/name`, from the URL since `gh pr view` doesn't report the repository.
    public var repository: String {
        let parts = url.pathComponents.filter { $0 != "/" }
        return parts.count >= 2 ? "\(parts[0])/\(parts[1])" : ""
    }

    public var checks: CheckSummary? {
        CheckSummary(outcomes: statusCheckRollup.map(\.outcome))
    }

    static let fields = [
        "number", "title", "body", "url", "state", "isDraft", "author", "headRefName", "baseRefName",
        "headRefOid", "reviewDecision", "statusCheckRollup", "latestReviews", "mergeable",
        "mergeStateStatus", "labels", "additions", "deletions", "createdAt", "updatedAt", "mergedAt",
        "closedAt", "isCrossRepository",
    ].joined(separator: ",")

    private enum CodingKeys: String, CodingKey {
        case number, title, body, url, state, isDraft, author, headRefName, baseRefName, headRefOid,
             reviewDecision, statusCheckRollup, latestReviews, mergeable, mergeStateStatus, labels,
             additions, deletions, createdAt, updatedAt, mergedAt, closedAt, isCrossRepository
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        number = try container.decode(Int.self, forKey: .number)
        title = try container.decode(String.self, forKey: .title)
        body = try container.decodeText(forKey: .body)
        url = try container.decode(URL.self, forKey: .url)
        state = try container.decodeEnum(State.self, forKey: .state) ?? .other
        isDraft = try container.decodeIfPresent(Bool.self, forKey: .isDraft) ?? false
        author = try container.decodeIfPresent(GitHubActor.self, forKey: .author)
        headRefName = try container.decodeIfPresent(String.self, forKey: .headRefName) ?? ""
        baseRefName = try container.decodeIfPresent(String.self, forKey: .baseRefName) ?? ""
        headRefOid = try container.decodeText(forKey: .headRefOid)
        reviewDecision = try container.decodeEnum(ReviewDecision.self, forKey: .reviewDecision)
        statusCheckRollup = try container.decodeIfPresent([StatusCheck].self, forKey: .statusCheckRollup) ?? []
        latestReviews = try container.decodeIfPresent([PullRequestReview].self, forKey: .latestReviews) ?? []
        mergeable = try container.decodeEnum(Mergeable.self, forKey: .mergeable)
        mergeStatus = try container.decodeEnum(MergeStatus.self, forKey: .mergeStateStatus)
        labels = try container.decodeIfPresent([PullRequestLabel].self, forKey: .labels) ?? []
        additions = try container.decodeIfPresent(Int.self, forKey: .additions)
        deletions = try container.decodeIfPresent(Int.self, forKey: .deletions)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        updatedAt = try container.decode(Date.self, forKey: .updatedAt)
        mergedAt = try container.decodeIfPresent(Date.self, forKey: .mergedAt)
        closedAt = try container.decodeIfPresent(Date.self, forKey: .closedAt)
        isCrossRepository = try container.decodeIfPresent(Bool.self, forKey: .isCrossRepository) ?? false
    }
}
