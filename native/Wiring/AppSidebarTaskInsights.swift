import ACP
import Foundation
import Git
import GitHub
import SwiftUI

/// The sidebar's answers from the Git and GitHub features: the filters' (whether a task has
/// uncommitted changes, a pull request) and its rows' pull request outcomes and menus. Like the task rows'
/// accessories, only a task with its own checkout (a worktree) has changes or a pull request of its
/// own; tasks in the project folder share its checkout.
@MainActor
enum AppSidebarTaskInsights {
    static func make(model: AppModel, git: GitStore, gitHub: GitHubModel) -> SidebarTaskInsights {
        let tasks = AppTaskPullRequests(model: model, git: git, gitHub: gitHub)
        return SidebarTaskInsights(
            source: ObjectIdentifier(model),
            hasUncommittedChanges: { summary in
                tasks.checkout(of: summary).map { git.model(for: $0, session: summary.id).isDirty } ?? false
            },
            hasPullRequest: { summary in
                tasks.pullRequest(of: summary) != nil
            },
            branch: { summary in
                guard let folder = tasks.checkout(of: summary) else { return nil }
                return git.model(for: folder, session: summary.id).branch?.name
            },
            prepareBranch: { summary in
                guard let folder = tasks.checkout(of: summary) else { return }
                let repository = git.model(for: folder, session: summary.id)
                if repository.isLocal, !FileManager.default.fileExists(atPath: folder.path) { return }
                if repository.status == nil { await repository.refreshNow() }
            },
            pullRequestBadge: { summary in
                tasks.pullRequest(of: summary).map { AnyView(SidebarPullRequestBadge(pullRequest: $0)) }
            },
            pullRequestMenu: { summary in
                tasks.menu(of: summary)
            },
            prepare: { summaries in
                for summary in summaries {
                    await tasks.prepare(summary)
                }
            }
        )
    }
}
