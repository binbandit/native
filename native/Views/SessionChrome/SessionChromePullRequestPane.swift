#if DEBUG
import SwiftUI

/// The task's branch and its pull request as a pane, or the way to open one.
struct SessionChromePullRequestPane: View {
    let context: SessionChromeContext

    var body: some View {
        Group {
            if let branch = context.branchReference, context.gitHub.pullRequest(for: branch) != nil {
                ScrollView {
                    TaskPullRequestCard(branch: branch) {}
                        .padding(DS.Space.lg)
                }
            } else {
                EmptyStateView(
                    "No pull request yet", systemImage: "arrow.triangle.branch",
                    message: context.branchName.map { "\($0) isn't in a pull request yet." }
                        ?? "This task isn't on a branch."
                ) {
                    if context.branchName != nil {
                        Button("Create Pull Request") {
                            Task {
                                await GitHubGitWiring.createPullRequest(
                                    from: context.repository, gitHub: context.gitHub)
                            }
                        }
                        .buttonStyle(.ds(.secondary))
                    }
                }
            }
        }
        .task(id: context.branchReference) {
            if let branch = context.branchReference { await context.gitHub.loadPullRequest(for: branch) }
        }
    }
}
#endif
