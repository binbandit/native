import Foundation

extension PullRequestSummary {
    /// The page's pull request as lists show it, for actions the page shares with the list.
    public init(_ page: PullRequestPage) {
        self.init(
            url: page.url, repository: page.reference.repository, number: page.reference.number, title: page.title,
            state: page.state, isDraft: page.isDraft, author: page.author.map { GitHubActor(login: $0) },
            labels: page.labels, createdAt: page.createdAt, updatedAt: page.updatedAt, headRefName: page.headRefName,
            baseRefName: page.baseRefName, reviewDecision: page.reviewDecision, mergeable: page.mergeable,
            checks: page.checks, additions: page.additions, deletions: page.deletions)
    }
}
