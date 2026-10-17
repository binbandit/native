import Foundation

/// A pull request as lists and badges show it, whichever command it came from. Fields search
/// can't provide stay `nil` until a status lookup fills them in.
public struct PullRequestSummary: Sendable, Hashable, Identifiable {
    public var url: URL
    /// `owner/name`.
    public var repository: String
    public var number: Int
    public var title: String
    public var state: PullRequest.State
    public var isDraft: Bool
    public var author: GitHubActor?
    public var labels: [PullRequestLabel]
    public var createdAt: Date
    public var updatedAt: Date
    public var headRefName: String?
    public var baseRefName: String?
    public var reviewDecision: PullRequest.ReviewDecision?
    public var mergeable: PullRequest.Mergeable?
    public var checks: CheckSummary?
    public var additions: Int?
    public var deletions: Int?
    public var commentsCount: Int?

    /// The URL is unique across hosts and repositories.
    public var id: URL { url }

    /// `owner/name#123`.
    public var reference: String {
        "\(repository)#\(number)"
    }

    public init(
        url: URL,
        repository: String,
        number: Int,
        title: String,
        state: PullRequest.State = .open,
        isDraft: Bool = false,
        author: GitHubActor? = nil,
        labels: [PullRequestLabel] = [],
        createdAt: Date,
        updatedAt: Date,
        headRefName: String? = nil,
        baseRefName: String? = nil,
        reviewDecision: PullRequest.ReviewDecision? = nil,
        mergeable: PullRequest.Mergeable? = nil,
        checks: CheckSummary? = nil,
        additions: Int? = nil,
        deletions: Int? = nil,
        commentsCount: Int? = nil
    ) {
        self.url = url
        self.repository = repository
        self.number = number
        self.title = title
        self.state = state
        self.isDraft = isDraft
        self.author = author
        self.labels = labels
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.headRefName = headRefName
        self.baseRefName = baseRefName
        self.reviewDecision = reviewDecision
        self.mergeable = mergeable
        self.checks = checks
        self.additions = additions
        self.deletions = deletions
        self.commentsCount = commentsCount
    }

    public init(_ pullRequest: PullRequest) {
        self.init(
            url: pullRequest.url,
            repository: pullRequest.repository,
            number: pullRequest.number,
            title: pullRequest.title,
            state: pullRequest.state,
            isDraft: pullRequest.isDraft,
            author: pullRequest.author,
            labels: pullRequest.labels,
            createdAt: pullRequest.createdAt,
            updatedAt: pullRequest.updatedAt,
            headRefName: pullRequest.headRefName,
            baseRefName: pullRequest.baseRefName,
            reviewDecision: pullRequest.reviewDecision,
            mergeable: pullRequest.mergeable,
            checks: pullRequest.checks,
            additions: pullRequest.additions,
            deletions: pullRequest.deletions
        )
    }

    public init(_ result: PullRequestSearchResult, status: PullRequestStatus?) {
        self.init(
            url: result.url,
            repository: result.repository,
            number: result.number,
            title: result.title,
            state: result.state,
            isDraft: result.isDraft,
            author: result.author,
            labels: result.labels,
            createdAt: result.createdAt,
            updatedAt: result.updatedAt,
            headRefName: status?.headRefName,
            baseRefName: status?.baseRefName,
            reviewDecision: status?.reviewDecision,
            mergeable: status?.mergeable,
            checks: status?.checks,
            additions: status?.additions,
            deletions: status?.deletions,
            commentsCount: result.commentsCount
        )
    }
}
