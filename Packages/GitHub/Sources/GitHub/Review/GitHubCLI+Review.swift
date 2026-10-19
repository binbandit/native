import Foundation

/// Reading and reviewing one pull request.
extension GitHubCLI {
    /// The same gh, aimed at the pull request's host.
    public func forPullRequest(_ reference: PullRequestReference) -> GitHubCLI {
        reference.ghHost == host ? self : targeting(host: reference.ghHost)
    }

    public func pullRequestPage(
        _ reference: PullRequestReference
    ) async throws(GitHubError)
        -> PullRequestPage
    {
        let data = try await forPullRequest(reference).run(.pullRequestPage(reference))
        guard let page = try PullRequestPage.decode(data, reference: reference) else {
            throw .notFound("\(reference.display) doesn't exist, or your account can't see it.")
        }
        return page
    }

    /// The next hundred conversation items after `cursor`, and where the following page starts.
    public func timeline(
        _ reference: PullRequestReference, after cursor: String
    )
        async throws(GitHubError) -> (
            items: [PullRequestTimelineItem], next: String?
        )
    {
        struct Payload: Decodable {
            struct Repository: Decodable {
                struct PullRequest: Decodable {
                    var timelineItems: Page<PullRequestTimelineItem>
                }

                var pullRequest: PullRequest
            }

            var repository: Repository
        }
        let data = try await forPullRequest(reference).run(.timelinePage(reference, after: cursor))
        let page = try GitHubJSON.decode(GraphQLResponse<Payload>.self, from: data).data.repository
            .pullRequest.timelineItems
        return (page.nodes, page.pageInfo.next)
    }

    /// The next hundred changed files after `cursor`.
    public func changedFiles(
        _ reference: PullRequestReference, after cursor: String
    )
        async throws(GitHubError) -> (
            files: [ChangedFile], next: String?
        )
    {
        struct Payload: Decodable {
            struct Repository: Decodable {
                struct PullRequest: Decodable {
                    var files: Page<ChangedFile>
                }

                var pullRequest: PullRequest
            }

            var repository: Repository
        }
        let data = try await forPullRequest(reference).run(.changedFilesPage(reference, after: cursor))
        let page = try GitHubJSON.decode(GraphQLResponse<Payload>.self, from: data).data.repository
            .pullRequest.files
        return (page.nodes, page.pageInfo.next)
    }

    /// One page (1-based) of a hundred files with their patches; empty past the last.
    public func filePatches(
        _ reference: PullRequestReference, page: Int
    ) async throws(GitHubError)
        -> [FilePatch]
    {
        try GitHubJSON.decode(
            [FilePatch].self,
            from: try await forPullRequest(reference).run(.filePatches(reference, page: page)))
    }

    // MARK: - Reviewing

    /// Starts the viewer's pending review and returns its id.
    public func startReview(_ page: PullRequestPage) async throws(GitHubError) -> String {
        try await reviewID(from: .startReview(pullRequestID: page.id, commit: page.headRefOid), page)
    }

    /// Posts one line comment right away, as a review of its own.
    public func addSingleComment(
        _ body: String, at anchor: ReviewAnchor, on page: PullRequestPage
    )
        async throws(GitHubError)
    {
        _ = try await run(
            page,
            .submitNewReview(
                pullRequestID: page.id, commit: page.headRefOid, event: .comment, body: "",
                comment: (anchor, body)))
    }

    /// Adds a line comment to the pending review, starting one if needed. Returns the review's id.
    @discardableResult
    public func addReviewComment(
        _ body: String, at anchor: ReviewAnchor, on page: PullRequestPage
    )
        async throws(GitHubError) -> String
    {
        let reviewID: String
        if let pending = page.pendingReview {
            reviewID = pending.id
        } else {
            reviewID = try await startReview(page)
        }
        _ = try await run(page, .addReviewThread(reviewID: reviewID, anchor: anchor, body: body))
        return reviewID
    }

    public func reply(
        _ body: String, to thread: ReviewThread, on page: PullRequestPage
    )
        async throws(GitHubError)
    {
        _ = try await run(
            page, .replyToThread(threadID: thread.id, body: body, reviewID: page.pendingReview?.id))
    }

    /// Submits the pending review, or a review without line comments when there's none.
    public func submitReview(
        _ event: ReviewEvent, body: String, on page: PullRequestPage
    )
        async throws(GitHubError)
    {
        if let pending = page.pendingReview {
            _ = try await run(page, .submitReview(reviewID: pending.id, event: event, body: body))
        } else {
            _ = try await run(
                page,
                .submitNewReview(pullRequestID: page.id, commit: page.headRefOid, event: event, body: body))
        }
    }

    public func discardReview(_ reviewID: String, on page: PullRequestPage) async throws(GitHubError) {
        _ = try await run(page, .discardReview(reviewID: reviewID))
    }

    public func updateReviewComment(
        _ comment: ReviewComment, body: String, on page: PullRequestPage
    )
        async throws(GitHubError)
    {
        _ = try await run(page, .updateReviewComment(commentID: comment.id, body: body))
    }

    public func deleteReviewComment(
        _ comment: ReviewComment, on page: PullRequestPage
    )
        async throws(GitHubError)
    {
        _ = try await run(page, .deleteReviewComment(commentID: comment.id))
    }

    public func setResolved(
        _ resolved: Bool, thread: ReviewThread, on page: PullRequestPage
    )
        async throws(GitHubError)
    {
        _ = try await run(page, .setThreadResolved(threadID: thread.id, resolved: resolved))
    }

    public func setViewed(
        _ viewed: Bool, path: String, on page: PullRequestPage
    )
        async throws(GitHubError)
    {
        _ = try await run(page, .setFileViewed(pullRequestID: page.id, path: path, viewed: viewed))
    }

    public func addComment(_ body: String, on page: PullRequestPage) async throws(GitHubError) {
        _ = try await run(page, .addComment(subjectID: page.id, body: body))
    }

    /// Merges at the commit the page shows, so a push that lands in between isn't merged unseen.
    /// `admin` merges past unmet requirements or the merge queue, for those allowed to.
    public func merge(
        _ page: PullRequestPage, method: MergeMethod, deleteBranch: Bool, admin: Bool = false
    )
        async throws(GitHubError)
    {
        let location = RepositoryLocation.remote(
            page.reference.ghHost.map { "\($0)/\(page.reference.repository)" }
                ?? page.reference.repository)
        try await forPullRequest(page.reference).merge(
            .number(page.reference.number), in: location, method: method, deleteBranch: deleteBranch,
            matchHeadCommit: page.headRefOid, admin: admin)
    }

    public func enqueue(_ page: PullRequestPage) async throws(GitHubError) {
        _ = try await run(page, .enqueue(pullRequestID: page.id, expectedHeadOid: page.headRefOid))
    }

    public func dequeue(_ page: PullRequestPage) async throws(GitHubError) {
        _ = try await run(page, .dequeue(pullRequestID: page.id))
    }

    public func enableAutoMerge(_ page: PullRequestPage, method: MergeMethod) async throws(GitHubError) {
        _ = try await run(
            page, .enableAutoMerge(pullRequestID: page.id, method: method, expectedHeadOid: page.headRefOid))
    }

    public func disableAutoMerge(_ page: PullRequestPage) async throws(GitHubError) {
        _ = try await run(page, .disableAutoMerge(pullRequestID: page.id))
    }

    private func run(
        _ page: PullRequestPage, _ command: GitHubCommand
    ) async throws(GitHubError)
        -> Data
    {
        try await forPullRequest(page.reference).run(command)
    }

    private func reviewID(
        from command: GitHubCommand, _ page: PullRequestPage
    )
        async throws(GitHubError) -> String
    {
        struct Payload: Decodable {
            struct Result: Decodable {
                struct Review: Decodable {
                    var id: String
                }

                var pullRequestReview: Review
            }

            var addPullRequestReview: Result
        }
        let data = try await run(page, command)
        return try GitHubJSON.decode(GraphQLResponse<Payload>.self, from: data).data
            .addPullRequestReview.pullRequestReview.id
    }
}
