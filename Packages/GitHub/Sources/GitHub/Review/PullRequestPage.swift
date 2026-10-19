import Foundation

/// Everything the pull request page opens with, from one GraphQL query: the pull request, what
/// the viewer may do, its conversation, review threads and the first hundred changed files.
public struct PullRequestPage: Sendable, Hashable {
    public var reference: PullRequestReference
    /// The node id mutations take.
    public var id: String
    public var viewerLogin: String
    public var permission: RepositoryPermission
    public var mergeMethods: [MergeMethod]
    public var defaultMergeMethod: MergeMethod?

    public var title: String
    public var body: String
    public var url: URL
    public var state: PullRequest.State
    public var isDraft: Bool
    public var author: String?
    public var createdAt: Date
    public var updatedAt: Date
    public var mergedAt: Date?
    public var closedAt: Date?
    public var headRefName: String
    public var baseRefName: String
    public var headRefOid: String
    public var isCrossRepository: Bool
    public var reviewDecision: PullRequest.ReviewDecision?
    public var mergeable: PullRequest.Mergeable?
    public var mergeStatus: PullRequest.MergeStatus?
    public var additions: Int
    public var deletions: Int
    public var changedFiles: Int
    public var viewerDidAuthor: Bool
    public var viewerCanMergeAsAdmin: Bool
    public var viewerCanClose: Bool
    public var viewerCanReopen: Bool
    public var viewerCanEnableAutoMerge: Bool
    public var viewerCanDisableAutoMerge: Bool
    /// The repository lets pull requests merge on their own once requirements pass.
    public var autoMergeAllowed: Bool
    /// The base branch merges through a merge queue.
    public var isMergeQueueEnabled: Bool
    /// How the base branch's merge queue merges, when it has one.
    public var mergeQueueMethod: MergeMethod?
    /// Queued or set to auto-merge, when it is.
    public var mergeState: PullRequestMergeState?
    /// Why it last left the merge queue, when that's the latest queue event.
    public var removedFromQueueReason: String?
    public var labels: [PullRequestLabel]
    public var requestedReviewers: [String]
    /// Each reviewer's latest approval or change request.
    public var latestReviews: [PullRequestReview]
    public var checks: CheckSummary?

    /// The viewer's review in progress, which only they can see.
    public var pendingReview: PendingReview?
    public var timeline: [PullRequestTimelineItem]
    public var timelineTotal: Int
    public var timelineCursor: String?
    public var threads: [ReviewThread]
    public var threadsTotal: Int
    public var files: [ChangedFile]
    public var filesCursor: String?

    public struct PendingReview: Sendable, Hashable {
        public var id: String
        public var commentCount: Int

        public init(id: String, commentCount: Int) {
            self.id = id
            self.commentCount = commentCount
        }
    }

    public var isOpen: Bool {
        state == .open
    }

    /// Whether the viewer may merge: push access, or admin rights that bypass protections.
    /// Close when it's open, Reopen when it's closed: GitHub says whether the viewer may.
    public var viewerCanCloseOrReopen: Bool {
        isOpen ? viewerCanClose : (state == .closed && viewerCanReopen)
    }

    public var viewerCanMerge: Bool {
        permission.canMerge || viewerCanMergeAsAdmin
    }

    /// GitHub refuses approvals and change requests from a pull request's own author.
    public var viewerCanApprove: Bool {
        !viewerDidAuthor
    }
}

// MARK: - Decoding

extension PullRequestPage {
    /// Decodes the page query's response, or `nil` when the repository has no such pull request.
    static func decode(
        _ data: Data, reference: PullRequestReference
    ) throws(GitHubError)
        -> PullRequestPage?
    {
        let response = try GitHubJSON.decode(GraphQLResponse<Payload>.self, from: data)
        guard let repository = response.data.repository, let pullRequest = repository.pullRequest else {
            return nil
        }
        return PullRequestPage(
            reference: reference, viewer: response.data.viewer.login, repository: repository,
            pullRequest: pullRequest)
    }

    private init(
        reference: PullRequestReference, viewer: String, repository: Payload.Repository,
        pullRequest: Payload.PullRequest
    ) {
        self.reference = reference
        id = pullRequest.id
        viewerLogin = viewer
        permission = RepositoryPermission(wire: repository.viewerPermission) ?? .read
        mergeMethods = [
            repository.mergeCommitAllowed == true ? MergeMethod.merge : nil,
            repository.squashMergeAllowed == true ? .squash : nil,
            repository.rebaseMergeAllowed == true ? .rebase : nil,
        ].compactMap(\.self)
        defaultMergeMethod = repository.viewerDefaultMergeMethod.flatMap {
            MergeMethod(rawValue: $0.lowercased())
        }
        title = pullRequest.title
        body = pullRequest.body ?? ""
        url = pullRequest.url
        state = PullRequest.State(wire: pullRequest.state) ?? .other
        isDraft = pullRequest.isDraft ?? false
        author = pullRequest.author?.login
        createdAt = pullRequest.createdAt
        updatedAt = pullRequest.updatedAt
        mergedAt = pullRequest.mergedAt
        closedAt = pullRequest.closedAt
        headRefName = pullRequest.headRefName
        baseRefName = pullRequest.baseRefName
        headRefOid = pullRequest.headRefOid
        isCrossRepository = pullRequest.isCrossRepository ?? false
        reviewDecision = PullRequest.ReviewDecision(wire: pullRequest.reviewDecision)
        mergeable = PullRequest.Mergeable(wire: pullRequest.mergeable)
        mergeStatus = PullRequest.MergeStatus(wire: pullRequest.mergeStateStatus)
        additions = pullRequest.additions ?? 0
        deletions = pullRequest.deletions ?? 0
        changedFiles = pullRequest.changedFiles ?? 0
        viewerDidAuthor = pullRequest.viewerDidAuthor ?? false
        viewerCanMergeAsAdmin = pullRequest.viewerCanMergeAsAdmin ?? false
        viewerCanClose = pullRequest.viewerCanClose ?? false
        viewerCanReopen = pullRequest.viewerCanReopen ?? false
        viewerCanEnableAutoMerge = pullRequest.viewerCanEnableAutoMerge ?? false
        viewerCanDisableAutoMerge = pullRequest.viewerCanDisableAutoMerge ?? false
        autoMergeAllowed = repository.autoMergeAllowed ?? false
        isMergeQueueEnabled = pullRequest.isMergeQueueEnabled ?? false
        mergeQueueMethod = pullRequest.mergeQueue?.configuration?.mergeMethod.flatMap {
            MergeMethod(rawValue: $0.lowercased())
        }
        mergeState = pullRequest.mergeStatePayload.state
        removedFromQueueReason = pullRequest.queueEvents?.nodes.last?.reason
        labels = pullRequest.labels?.nodes ?? []
        requestedReviewers = (pullRequest.reviewRequests?.nodes ?? []).compactMap {
            $0.requestedReviewer?.name
        }
        latestReviews = pullRequest.latestOpinionatedReviews?.nodes ?? []
        checks = pullRequest.commits?.rollup?.summary
        pendingReview = pullRequest.reviews?.nodes.first.map {
            PendingReview(id: $0.id, commentCount: $0.comments?.totalCount ?? 0)
        }
        timeline = pullRequest.timelineItems.nodes
        timelineTotal = pullRequest.timelineItems.totalCount
        timelineCursor = pullRequest.timelineItems.pageInfo.next
        threads = pullRequest.reviewThreads.nodes
        threadsTotal = pullRequest.reviewThreads.totalCount
        files = pullRequest.files.nodes
        filesCursor = pullRequest.files.pageInfo.next
    }

    private struct Payload: Decodable {
        struct Viewer: Decodable {
            var login: String
        }

        struct Repository: Decodable {
            var viewerPermission: String?
            var mergeCommitAllowed: Bool?
            var squashMergeAllowed: Bool?
            var rebaseMergeAllowed: Bool?
            var viewerDefaultMergeMethod: String?
            var autoMergeAllowed: Bool?
            var pullRequest: PullRequest?
        }

        struct PullRequest: Decodable {
            var id: String
            var title: String
            var body: String?
            var url: URL
            var state: String
            var isDraft: Bool?
            var author: TimelineLogin?
            var createdAt: Date
            var updatedAt: Date
            var mergedAt: Date?
            var closedAt: Date?
            var headRefName: String
            var baseRefName: String
            var headRefOid: String
            var isCrossRepository: Bool?
            var reviewDecision: String?
            var mergeable: String?
            var mergeStateStatus: String?
            var additions: Int?
            var deletions: Int?
            var changedFiles: Int?
            var viewerDidAuthor: Bool?
            var viewerCanMergeAsAdmin: Bool?
            var viewerCanClose: Bool?
            var viewerCanReopen: Bool?
            var viewerCanEnableAutoMerge: Bool?
            var viewerCanDisableAutoMerge: Bool?
            var isMergeQueueEnabled: Bool?
            var mergeQueue: MergeQueue?
            var mergeQueueEntry: PullRequestMergeState.Payload.Entry?
            var autoMergeRequest: PullRequestMergeState.Payload.AutoMerge?
            var queueEvents: Nodes<QueueEvent>?
            var labels: Nodes<PullRequestLabel>?
            var reviewRequests: Nodes<ReviewRequest>?
            var latestOpinionatedReviews: Nodes<PullRequestReview>?
            var commits: CheckRollup.LastCommit?
            var reviews: Nodes<Pending>?
            var timelineItems: Page<PullRequestTimelineItem>
            var reviewThreads: Page<ReviewThread>
            var files: Page<ChangedFile>

            var mergeStatePayload: PullRequestMergeState.Payload {
                PullRequestMergeState.Payload(mergeQueueEntry: mergeQueueEntry, autoMergeRequest: autoMergeRequest)
            }
        }

        struct ReviewRequest: Decodable {
            struct Reviewer: Decodable {
                var login: String?
                var teamName: String?

                var name: String? { login ?? teamName }

                private enum CodingKeys: String, CodingKey {
                    case login
                    case teamName = "name"
                }
            }

            var requestedReviewer: Reviewer?
        }

        struct MergeQueue: Decodable {
            struct Configuration: Decodable {
                var mergeMethod: String?
            }

            var configuration: Configuration?
        }

        /// The latest queue event; only a removal has a reason.
        struct QueueEvent: Decodable {
            var reason: String?
        }

        struct Pending: Decodable {
            struct Count: Decodable {
                var totalCount: Int
            }

            var id: String
            var comments: Count?
        }

        var viewer: Viewer
        var repository: Repository?
    }
}
