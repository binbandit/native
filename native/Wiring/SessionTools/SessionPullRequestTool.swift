import Git
import GitHub
import SessionTools
import SwiftUI

/// The branch's pull request as a session tool: "#123" under the title once the branch has one,
/// and the pull request at a glance as its pane, or the way to open one.
@MainActor
enum SessionPullRequestTool {
    static func contribution(git: GitStore, gitHub: GitHubModel) -> SessionToolContribution {
        let branch = { (context: SessionToolContext) -> BranchReference? in
            guard case .branch(let name)? = git.model(for: context.session.cwd).branch?.head else { return nil }
            return BranchReference(directory: context.session.cwd, branch: name)
        }
        return SessionToolContribution(
            spec: SessionToolSpec(id: .pullRequest, places: [.fact, .side, .off], defaultPlace: .fact),
            title: "Pull Request", systemImage: "arrow.triangle.pull",
            fact: { context in
                branch(context).flatMap(gitHub.pullRequest(for:)).map { SessionToolFact(text: "#\($0.number)") }
            },
            hasContent: { branch($0).flatMap(gitHub.pullRequest(for:)) != nil },
            pane: { context in
                AnyView(
                    SessionPullRequestPane(branch: branch(context), repository: git.model(for: context.session.cwd)))
            })
    }
}

/// The pull request, or what to do about having none.
private struct SessionPullRequestPane: View {
    let branch: BranchReference?
    let repository: GitRepositoryModel
    @Environment(GitHubModel.self) private var gitHub

    var body: some View {
        Group {
            if let branch, gitHub.pullRequest(for: branch) != nil {
                ScrollView {
                    TaskPullRequestCard(branch: branch) {}
                        .padding(DS.Space.lg)
                }
            } else if let branch {
                EmptyStateView(
                    "No pull request yet", systemImage: "arrow.triangle.pull",
                    message: "\(branch.branch) isn't in a pull request. Open one to get it reviewed."
                ) {
                    Button("Create Pull Request") {
                        Task { await GitHubGitWiring.createPullRequest(from: repository, gitHub: gitHub) }
                    }
                    .buttonStyle(.ds(.secondary))
                }
            } else {
                EmptyStateView(
                    "Not on a branch", systemImage: "arrow.triangle.pull",
                    message: "Pull requests come from branches, and this task's folder isn't on one.")
            }
        }
        .task(id: branch) {
            if let branch { await gitHub.loadPullRequest(for: branch) }
        }
    }
}
