import Foundation

// The pull request page's reads, and the review writes. Each write is one GraphQL mutation, so a
// failure leaves nothing half done.

extension GitHubCommand {
    static func graphQL(
        _ query: String, _ variables: [String: GraphQLRequest.Value], isMutating: Bool = false
    ) -> GitHubCommand {
        GitHubCommand(
            ["api", "graphql", "--input", "-"],
            input: GraphQLRequest(query: query, variables: variables).data,
            isMutating: isMutating)
    }

    private static func variables(_ reference: PullRequestReference) -> [String: GraphQLRequest.Value] {
        [
            "owner": .string(reference.owner), "name": .string(reference.name),
            "number": .int(reference.number),
        ]
    }

    public static func pullRequestPage(_ reference: PullRequestReference) -> GitHubCommand {
        graphQL(PullRequestQueries.page, variables(reference))
    }

    public static func timelinePage(
        _ reference: PullRequestReference, after cursor: String
    )
        -> GitHubCommand
    {
        graphQL(
            PullRequestQueries.timeline, variables(reference).merging(["after": .string(cursor)]) { $1 })
    }

    public static func changedFilesPage(
        _ reference: PullRequestReference, after cursor: String
    )
        -> GitHubCommand
    {
        graphQL(
            PullRequestQueries.files, variables(reference).merging(["after": .string(cursor)]) { $1 })
    }

    /// REST is the only API with patches. Pages hold 100 files, in the diff's order.
    public static func filePatches(_ reference: PullRequestReference, page: Int) -> GitHubCommand {
        GitHubCommand([
            "api",
            "repos/\(reference.owner)/\(reference.name)/pulls/\(reference.number)/files?per_page=100&page=\(page)",
        ])
    }
}

// MARK: - Writes

extension GitHubCommand {
    private static func mutation(
        _ name: String, _ input: [String: GraphQLRequest.Value],
        returning selection: String = "clientMutationId"
    ) -> GitHubCommand {
        let query =
            "mutation($input: \(name.prefix(1).uppercased() + name.dropFirst())Input!) { \(name)(input: $input) { \(selection) } }"
        return graphQL(query, ["input": .object(input)], isMutating: true)
    }

    private static func thread(_ anchor: ReviewAnchor, body: String) -> [String: GraphQLRequest.Value] {
        var thread: [String: GraphQLRequest.Value] = [
            "path": .string(anchor.path), "body": .string(body), "line": .int(anchor.line),
            "side": .string(anchor.side.rawValue),
        ]
        if let startLine = anchor.startLine {
            thread["startLine"] = .int(startLine)
            thread["startSide"] = .string((anchor.startSide ?? anchor.side).rawValue)
        }
        return thread
    }

    /// Starts the viewer's pending review, at the commit they're looking at.
    public static func startReview(pullRequestID: String, commit: String) -> GitHubCommand {
        mutation(
            "addPullRequestReview",
            ["pullRequestId": .string(pullRequestID), "commitOID": .string(commit)],
            returning: "pullRequestReview { id }")
    }

    /// Submits a review in one step: a single line comment, or a verdict with no pending comments.
    public static func submitNewReview(
        pullRequestID: String, commit: String, event: ReviewEvent, body: String,
        comment: (anchor: ReviewAnchor, body: String)? = nil
    ) -> GitHubCommand {
        var input: [String: GraphQLRequest.Value] = [
            "pullRequestId": .string(pullRequestID), "commitOID": .string(commit),
            "event": .string(event.rawValue),
        ]
        if !body.isEmpty { input["body"] = .string(body) }
        if let comment {
            input["threads"] = .array([.object(thread(comment.anchor, body: comment.body))])
        }
        return mutation("addPullRequestReview", input, returning: "pullRequestReview { id }")
    }

    /// Adds a line comment to the pending review.
    public static func addReviewThread(
        reviewID: String, anchor: ReviewAnchor, body: String
    )
        -> GitHubCommand
    {
        var input = thread(anchor, body: body)
        input["pullRequestReviewId"] = .string(reviewID)
        return mutation("addPullRequestReviewThread", input, returning: "thread { id }")
    }

    /// Replies in a thread. With a pending review the reply joins it, as on GitHub.
    public static func replyToThread(
        threadID: String, body: String, reviewID: String?
    )
        -> GitHubCommand
    {
        var input: [String: GraphQLRequest.Value] = [
            "pullRequestReviewThreadId": .string(threadID), "body": .string(body),
        ]
        if let reviewID { input["pullRequestReviewId"] = .string(reviewID) }
        return mutation("addPullRequestReviewThreadReply", input, returning: "comment { id }")
    }

    public static func submitReview(
        reviewID: String, event: ReviewEvent, body: String
    )
        -> GitHubCommand
    {
        var input: [String: GraphQLRequest.Value] = [
            "pullRequestReviewId": .string(reviewID), "event": .string(event.rawValue),
        ]
        if !body.isEmpty { input["body"] = .string(body) }
        return mutation("submitPullRequestReview", input, returning: "pullRequestReview { id }")
    }

    /// Discards the pending review and its comments.
    public static func discardReview(reviewID: String) -> GitHubCommand {
        mutation("deletePullRequestReview", ["pullRequestReviewId": .string(reviewID)])
    }

    public static func updateReviewComment(commentID: String, body: String) -> GitHubCommand {
        mutation(
            "updatePullRequestReviewComment",
            ["pullRequestReviewCommentId": .string(commentID), "body": .string(body)])
    }

    public static func deleteReviewComment(commentID: String) -> GitHubCommand {
        mutation("deletePullRequestReviewComment", ["id": .string(commentID)])
    }

    public static func setThreadResolved(threadID: String, resolved: Bool) -> GitHubCommand {
        mutation(
            resolved ? "resolveReviewThread" : "unresolveReviewThread", ["threadId": .string(threadID)])
    }

    public static func setFileViewed(
        pullRequestID: String, path: String, viewed: Bool
    )
        -> GitHubCommand
    {
        mutation(
            viewed ? "markFileAsViewed" : "unmarkFileAsViewed",
            ["pullRequestId": .string(pullRequestID), "path": .string(path)])
    }

    /// A comment on the conversation.
    public static func addComment(subjectID: String, body: String) -> GitHubCommand {
        mutation("addComment", ["subjectId": .string(subjectID), "body": .string(body)])
    }
}
