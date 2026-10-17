import GitHub
import SwiftUI

/// The pull request for a task's branch, looked up through gh and shared with every other badge on
/// the same branch. Shows nothing while loading or when the branch has none, so it can sit in a
/// row unconditionally.
struct TaskPullRequestBadge: View {
    /// The task's checkout (its worktree).
    let directory: URL
    let branch: String
    var style: PullRequestBadge.Style = .compact

    @Environment(GitHubModel.self) private var model

    var body: some View {
        let reference = BranchReference(directory: directory, branch: branch)
        Group {
            if let pullRequest = model.pullRequest(for: reference) {
                PullRequestBadge(pullRequest: pullRequest, style: style)
            }
        }
        .task(id: reference) {
            await model.loadPullRequest(for: reference)
        }
    }
}
