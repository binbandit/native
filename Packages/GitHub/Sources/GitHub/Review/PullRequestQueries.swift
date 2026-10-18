import Foundation

/// The GraphQL behind the pull request page. One query loads everything the page opens with, so
/// opening a pull request costs one request; files and timeline beyond the first hundred, and
/// patches, load as they're needed.
enum PullRequestQueries {
    static let timelineTypes = """
        ISSUE_COMMENT, PULL_REQUEST_REVIEW, PULL_REQUEST_COMMIT, HEAD_REF_FORCE_PUSHED_EVENT, LABELED_EVENT, \
        UNLABELED_EVENT, REVIEW_REQUESTED_EVENT, MERGED_EVENT, CLOSED_EVENT, REOPENED_EVENT, READY_FOR_REVIEW_EVENT, \
        CONVERT_TO_DRAFT_EVENT, RENAMED_TITLE_EVENT
        """

    static let timelineNode = """
        __typename
        ... on IssueComment { id author { login } body createdAt lastEditedAt url viewerCanUpdate viewerCanDelete }
        ... on PullRequestReview { id author { login } state body submittedAt createdAt url comments { totalCount } }
        ... on PullRequestCommit { id commit { oid abbreviatedOid messageHeadline committedDate author { name user { login } } } }
        ... on HeadRefForcePushedEvent { id actor { login } createdAt beforeCommit { abbreviatedOid } afterCommit { abbreviatedOid } }
        ... on LabeledEvent { id actor { login } createdAt label { name color } }
        ... on UnlabeledEvent { id actor { login } createdAt label { name color } }
        ... on ReviewRequestedEvent { id actor { login } createdAt requestedReviewer { ... on User { login } ... on Team { name } ... on Bot { login } } }
        ... on MergedEvent { id actor { login } createdAt commit { abbreviatedOid } mergeRefName }
        ... on ClosedEvent { id actor { login } createdAt }
        ... on ReopenedEvent { id actor { login } createdAt }
        ... on ReadyForReviewEvent { id actor { login } createdAt }
        ... on ConvertToDraftEvent { id actor { login } createdAt }
        ... on RenamedTitleEvent { id actor { login } createdAt previousTitle currentTitle }
        """

    static let threadNode = """
        id isResolved isOutdated path line startLine originalLine diffSide startDiffSide subjectType
        viewerCanResolve viewerCanUnresolve viewerCanReply resolvedBy { login }
        comments(first: 50) { nodes { id author { login } body createdAt lastEditedAt url diffHunk state viewerCanUpdate viewerCanDelete } }
        """

    static let fileNode = "path additions deletions changeType viewerViewedState"

    static let page = """
        query($owner: String!, $name: String!, $number: Int!) {
          viewer { login }
          repository(owner: $owner, name: $name) {
            viewerPermission
            mergeCommitAllowed squashMergeAllowed rebaseMergeAllowed viewerDefaultMergeMethod
            pullRequest(number: $number) {
              id number title body url state isDraft
              author { login }
              createdAt updatedAt mergedAt closedAt
              headRefName baseRefName headRefOid isCrossRepository
              reviewDecision mergeable mergeStateStatus
              additions deletions changedFiles
              viewerDidAuthor viewerCanMergeAsAdmin
              labels(first: 20) { nodes { name color description } }
              reviewRequests(first: 20) { nodes { requestedReviewer { ... on User { login } ... on Team { name } ... on Bot { login } } } }
              latestOpinionatedReviews(first: 20) { nodes { author { login } state submittedAt } }
              commits(last: 1) { nodes { commit { oid statusCheckRollup { state contexts { checkRunCountsByState { state count } statusContextCountsByState { state count } } } } } }
              reviews(first: 1, states: [PENDING]) { nodes { id comments { totalCount } } }
              timelineItems(first: 100, itemTypes: [\(timelineTypes)]) {
                totalCount pageInfo { hasNextPage endCursor }
                nodes { \(timelineNode) }
              }
              reviewThreads(first: 100) { totalCount nodes { \(threadNode) } }
              files(first: 100) { totalCount pageInfo { hasNextPage endCursor } nodes { \(fileNode) } }
            }
          }
        }
        """

    static let timeline = """
        query($owner: String!, $name: String!, $number: Int!, $after: String!) {
          repository(owner: $owner, name: $name) {
            pullRequest(number: $number) {
              timelineItems(first: 100, after: $after, itemTypes: [\(timelineTypes)]) {
                totalCount pageInfo { hasNextPage endCursor }
                nodes { \(timelineNode) }
              }
            }
          }
        }
        """

    static let files = """
        query($owner: String!, $name: String!, $number: Int!, $after: String!) {
          repository(owner: $owner, name: $name) {
            pullRequest(number: $number) {
              files(first: 100, after: $after) { totalCount pageInfo { hasNextPage endCursor } nodes { \(fileNode) } }
            }
          }
        }
        """
}
