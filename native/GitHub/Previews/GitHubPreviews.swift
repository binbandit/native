import GitHub
import SwiftUI

#Preview("Pull Requests") {
    PullRequestsView()
        .environment(GitHubModel.preview(inbox: PullRequestPreviewFixtures.inbox))
        .frame(width: 900, height: 720)
}

#Preview("Pull Requests - Offline") {
    PullRequestsView()
        .environment(
            GitHubModel.preview(
                inbox: PullRequestPreviewFixtures.inbox, error: .offline("error connecting to api.github.com"))
        )
        .frame(width: 900, height: 480)
}

#Preview("GitHub CLI Missing") {
    PullRequestsView()
        .environment(GitHubModel.preview(availability: .notInstalled, error: .notInstalled))
        .frame(width: 900, height: 480)
}

#Preview("Not Signed In") {
    PullRequestsView()
        .environment(GitHubModel.preview(availability: .notAuthenticated, error: .notAuthenticated("")))
        .frame(width: 900, height: 480)
}

#Preview("Badges") {
    DSPreviewPair {
        VStack(alignment: .leading, spacing: DS.Space.lg) {
            ForEach(PullRequestPreviewFixtures.inbox.all.prefix(4)) { pullRequest in
                HStack(spacing: DS.Space.lg) {
                    PullRequestBadge(pullRequest: pullRequest, style: .regular)
                    PullRequestBadge(pullRequest: pullRequest, style: .compact)
                }
            }
            PullRequestsNavItem(isSelected: false) {}
                .frame(width: DS.Size.sidebarWidth)
        }
    }
    .environment(GitHubModel.preview(inbox: PullRequestPreviewFixtures.inbox))
}

#Preview("Create Pull Request") {
    CreatePullRequestSheet(request: PullRequestPreviewFixtures.createRequest)
        .environment(GitHubModel.preview())
}
