import ACP
import Foundation
import Git
import GitHub

/// Which pull request belongs to a task, for its sidebar row and the task commands. Like the row's
/// accessory, only a task with its own checkout (a worktree) has a branch, and so a pull request,
/// of its own; tasks in the project folder share its checkout.
@MainActor
struct AppTaskPullRequests {
    let model: AppModel
    let git: GitStore
    let gitHub: GitHubModel

    func checkout(of summary: SessionSummary) -> URL? {
        checkout(project: summary.project, cwd: summary.info.cwd)
    }

    func branch(of summary: SessionSummary) -> BranchReference? {
        guard let folder = checkout(of: summary), let branch = git.model(for: folder).branch?.name else { return nil }
        return BranchReference(directory: folder, branch: branch)
    }

    func pullRequest(of summary: SessionSummary) -> PullRequestSummary? {
        branch(of: summary).flatMap(gitHub.pullRequest(for:))
    }

    /// The pull request of a task by its key: the visible one, for a command.
    func pullRequest(for key: SessionKey) -> PullRequestSummary? {
        guard let found = model.catalog.lookup(key),
            let folder = checkout(project: found.project, cwd: found.info.cwd),
            let branch = git.model(for: folder).branch?.name
        else { return nil }
        return gitHub.pullRequest(for: BranchReference(directory: folder, branch: branch))
    }

    /// The row's "Pull Request" submenu: the hover card's actions.
    func menu(of summary: SessionSummary) -> SidebarTaskMenu? {
        guard let pullRequest = pullRequest(of: summary) else { return nil }
        var items = [
            SidebarTaskMenu.Item(title: "Open in Native", spokenTitle: "Open Pull Request in Native") {
                gitHub.openInNative(pullRequest)
            },
            SidebarTaskMenu.Item(title: "Open on GitHub", spokenTitle: "Open Pull Request on GitHub") {
                gitHub.openInBrowser(pullRequest)
            },
            SidebarTaskMenu.Item(title: "Copy Link", spokenTitle: "Copy Pull Request Link") {
                gitHub.copyURL(pullRequest)
            },
        ]
        if gitHub.offersMerge(pullRequest) {
            items.append(
                SidebarTaskMenu.Item(title: "Merge…", spokenTitle: "Merge Pull Request…") {
                    gitHub.requestMerge(pullRequest)
                })
        }
        return SidebarTaskMenu(title: "Pull Request", spokenSummary: pullRequest.spokenSummary, items: items)
    }

    private func checkout(project id: Project.ID, cwd: String) -> URL? {
        guard let project = model.projects.project(id), !SessionFolder.isSame(cwd, project.path) else { return nil }
        return URL(filePath: cwd, directoryHint: .isDirectory)
    }
}
