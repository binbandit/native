import ACP
import Foundation
import Git
import GitHub

/// The sidebar filters' answers from the Git and GitHub features. Like the task rows'
/// accessories, only a task with its own checkout (a worktree) has changes or a pull request of its
/// own; tasks in the project folder share its checkout.
@MainActor
enum AppSidebarTaskInsights {
    static func make(model: AppModel, git: GitStore, gitHub: GitHubModel) -> SidebarTaskInsights {
        func ownCheckout(of summary: SessionSummary) -> URL? {
            guard let project = model.projects.project(summary.project),
                !SessionFolder.isSame(summary.info.cwd, project.path)
            else { return nil }
            return URL(filePath: summary.info.cwd, directoryHint: .isDirectory)
        }
        func pullRequestReference(of summary: SessionSummary) -> BranchReference? {
            guard let folder = ownCheckout(of: summary), let branch = git.model(for: folder).branch?.name else {
                return nil
            }
            return BranchReference(directory: folder, branch: branch)
        }
        return SidebarTaskInsights(
            hasUncommittedChanges: { summary in
                ownCheckout(of: summary).map { git.model(for: $0).isDirty } ?? false
            },
            hasPullRequest: { summary in
                pullRequestReference(of: summary).map { gitHub.pullRequest(for: $0) != nil } ?? false
            },
            prepare: { summaries in
                for summary in summaries {
                    guard let folder = ownCheckout(of: summary), FileManager.default.fileExists(atPath: folder.path)
                    else { continue }
                    let repository = git.model(for: folder)
                    if repository.status == nil { await repository.refreshNow() }
                    if let reference = pullRequestReference(of: summary) {
                        await gitHub.loadPullRequest(for: reference)
                    }
                }
            }
        )
    }
}
