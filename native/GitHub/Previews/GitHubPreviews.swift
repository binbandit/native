import GitHub
import SwiftUI

#if DEBUG
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
    let pullRequests = Array(PullRequestPreviewFixtures.inbox.all.prefix(4))
    let folder = URL(filePath: "/tmp/preview", directoryHint: .isDirectory)
    let branches = Dictionary(
        pullRequests.map { (BranchReference(directory: folder, branch: $0.headRefName ?? "\($0.number)"), $0) },
        uniquingKeysWith: { first, _ in first })
    DSPreviewPair {
        VStack(alignment: .leading, spacing: DS.Space.lg) {
            ForEach(pullRequests) { pullRequest in
                HStack(spacing: DS.Space.lg) {
                    PullRequestBadge(pullRequest: pullRequest)
                    TaskPullRequestBadge(directory: folder, branch: pullRequest.headRefName ?? "\(pullRequest.number)")
                }
            }
            PullRequestsNavItem(isSelected: false) {}
                .frame(width: DS.Size.sidebarWidth)
        }
    }
    .environment(GitHubModel.preview(inbox: PullRequestPreviewFixtures.inbox, branches: branches))
}

#Preview("Task Pull Request Card") {
    let pullRequest = PullRequestPreviewFixtures.inbox.authored[0]
    let branch = BranchReference(
        directory: URL(filePath: "/tmp/preview", directoryHint: .isDirectory), branch: pullRequest.headRefName ?? "")
    DSPreviewPair {
        TaskPullRequestCard(branch: branch) {}
            .dsOverlayBackground(in: .rect(cornerRadius: DS.Radius.panel))
    }
    .environment(GitHubModel.preview(branches: [branch: pullRequest]))
}

#Preview("Create Pull Request") {
    CreatePullRequestSheet(request: PullRequestPreviewFixtures.createRequest)
        .environment(GitHubModel.preview())
}
#endif
