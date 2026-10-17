import Foundation
import GitHub

/// Pull requests shaped like the ones gh returns, for previews and render checks.
enum PullRequestPreviewFixtures {
    static let now = Date.now

    static func summary(
        _ repository: String,
        _ number: Int,
        _ title: String,
        branch: String,
        minutesAgo: Double,
        isDraft: Bool = false,
        state: PullRequest.State = .open,
        author: String = "binbandit",
        review: PullRequest.ReviewDecision? = nil,
        checks: CheckSummary? = CheckSummary(state: .passing, passed: 9, skipped: 1),
        size: (Int, Int) = (120, 14)
    ) -> PullRequestSummary {
        PullRequestSummary(
            url: URL(filePath: "/\(repository)/pull/\(number)"),
            repository: repository,
            number: number,
            title: title,
            state: state,
            isDraft: isDraft,
            author: GitHubActor(login: author),
            createdAt: now.addingTimeInterval(-minutesAgo * 60 - 3_600),
            updatedAt: now.addingTimeInterval(-minutesAgo * 60),
            headRefName: branch,
            baseRefName: "main",
            reviewDecision: review,
            checks: checks,
            additions: size.0,
            deletions: size.1
        )
    }

    static let inbox = PullRequestInbox(
        authored: [
            summary(
                "binbandit/oh-fx", 974,
                "feat(gateway): keep a generation without exact billing pending for reconciliation",
                branch: "ai/gateway-10b-deferred-usage", minutesAgo: 14,
                checks: CheckSummary(state: .failing, passed: 9, failed: 1, skipped: 1), size: (700, 59)),
            summary(
                "binbandit/oh-fx", 972, "feat(exec): manage terminal executions and observe their terminals",
                branch: "ai/tty-5-observer", minutesAgo: 52,
                checks: CheckSummary(state: .pending, passed: 6, pending: 4), size: (1_583, 49)),
            summary(
                "binbandit/yip", 52, "Detect configured model gateways in the runner environment",
                branch: "detect-gateways", minutesAgo: 60 * 30, review: .approved, size: (214, 31)),
            summary(
                "maximhq/bifrost", 2584, "fix(ui): restore pointer cursor on alert dialog buttons",
                branch: "fix-button-cursors", minutesAgo: 60 * 24 * 9, review: .reviewRequired, size: (2, 2)),
            summary(
                "binbandit/elara", 1, "Add home presence detection via network scanning", branch: "presence",
                minutesAgo: 60 * 24 * 40, isDraft: true, checks: nil, size: (412, 0)),
        ],
        reviewRequested: [
            summary(
                "WastedHippie/pier-sandbox-api", 6, "Rate limit /users to 60 requests a minute per client",
                branch: "rate-limit", minutesAgo: 60 * 5, author: "sage-smudge", review: .reviewRequired, size: (88, 4)),
            summary(
                "binbandit/handbook", 7, "build(deps): bump actions/setup-node from 7.0.0 to 7.1.0",
                branch: "dependabot/github_actions/actions/setup-node-7.1.0", minutesAgo: 60 * 26,
                author: "dependabot[bot]", review: .changesRequested, size: (1, 1)),
        ],
        assigned: [],
        fetchedAt: now.addingTimeInterval(-90)
    )

    static let createRequest = CreatePullRequestRequest(
        directory: URL(filePath: "/tmp/oh-fx"),
        head: "ai/gateway-10b-deferred-usage",
        commits: """
            ca006cb feat(gateway): keep a generation without exact billing pending for reconciliation
            7f1e2aa test(gateway): cover deferred settlement
            """
    )
}
