import ACP
import Foundation
import Git
import GitHub

/// The sidebar's answers from the Git and GitHub features: the filters' (whether a task has
/// uncommitted changes, a pull request) and its rows' pull request menus. Like the task rows'
/// accessories, only a task with its own checkout (a worktree) has changes or a pull request of its
/// own; tasks in the project folder share its checkout.
@MainActor
enum AppSidebarTaskInsights {
    static func make(model: AppModel, git: GitStore, gitHub: GitHubModel) -> SidebarTaskInsights {
        let tasks = AppTaskPullRequests(model: model, git: git, gitHub: gitHub)
        return SidebarTaskInsights(
            source: ObjectIdentifier(model),
            hasUncommittedChanges: { summary in
                tasks.checkout(of: summary).map { git.model(for: $0).isDirty } ?? false
            },
            hasPullRequest: { summary in
                tasks.pullRequest(of: summary) != nil
            },
            pullRequestMenu: { summary in
                tasks.menu(of: summary)
            },
            prepare: { summaries in
                for summary in summaries {
                    guard let folder = tasks.checkout(of: summary), FileManager.default.fileExists(atPath: folder.path)
                    else { continue }
                    let repository = git.model(for: folder)
                    if repository.status == nil { await repository.refreshNow() }
                    if let reference = tasks.branch(of: summary) {
                        await gitHub.loadPullRequest(for: reference)
                    }
                }
            }
        )
    }
}
