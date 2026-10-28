import ACP
import Foundation
import Git
import GitHub

/// Which pull request belongs to a task, for its sidebar row and the task commands. Like the row's
/// accessory, only a task with its own checkout (a worktree) has a branch, and so a pull request,
/// of its own; tasks in the project folder share its checkout. A task on a paired host is looked up
/// with gh on that host (`BranchReference.host`), never with this Mac's for the same path.
///
/// A paired host's pull request is read-only here for now: its menu opens it on GitHub or copies
/// its link, and `pullRequest(for:)` stays this Mac's, since the pull request page's merge, close
/// and comment act as this Mac's GitHub account rather than the host's.
@MainActor
struct AppTaskPullRequests {
    let model: AppModel
    let git: GitStore
    let gitHub: GitHubModel

    func checkout(of summary: SessionSummary) -> URL? {
        checkout(of: summary.id, project: summary.project, cwd: summary.info.cwd)
    }

    func branch(of summary: SessionSummary) -> BranchReference? {
        branch(of: summary.id, project: summary.project, cwd: summary.info.cwd)
    }

    /// A task's branch by its key, on whichever machine the task runs.
    func branch(for key: SessionKey) -> BranchReference? {
        guard let found = model.catalog.lookup(key) else { return nil }
        return branch(of: key, project: found.project, cwd: found.info.cwd)
    }

    func pullRequest(of summary: SessionSummary) -> PullRequestSummary? {
        branch(of: summary).flatMap(knownPullRequest(of:))
    }

    /// An archive's checkout may have been removed. Its saved branch is looked up from the project's
    /// surviving checkout on the same machine, so a relaunch needs neither a live worktree nor a PR cache.
    @discardableResult
    func prepare(_ summary: SessionSummary, maxAge: TimeInterval = GitHubModel.branchMaxAge) async -> GitHubError? {
        guard let folder = checkout(of: summary) else { return nil }
        if model.isArchived(summary.id), let project = projectCheckout(for: summary.id, in: summary.project) {
            try? await git.prepareArchivedTaskBranches(of: project, session: summary.id)
            if let reference = archivedBranch(of: summary.id, project: summary.project, folder: folder) {
                return await gitHub.loadPullRequest(for: reference, maxAge: maxAge)
            }
        }
        let repository = git.model(for: folder, session: summary.id)
        if repository.isLocal, !FileManager.default.fileExists(atPath: folder.path) { return nil }
        if repository.status == nil { await repository.refreshNow() }
        guard let reference = branch(of: summary) else { return nil }
        return await gitHub.loadPullRequest(for: reference, maxAge: maxAge)
    }

    /// The pull request of a task on this Mac by its key: the visible one, for the commands that open
    /// it where Settings say (the pull request page included). `branch(for:)` finds any task's.
    func pullRequest(for key: SessionKey) -> PullRequestSummary? {
        guard let branch = branch(for: key), branch.host == nil else { return nil }
        return gitHub.pullRequest(for: branch)
    }

    /// The row's "Pull Request" submenu: the hover card's actions.
    func menu(of summary: SessionSummary) -> SidebarTaskMenu? {
        guard let branch = branch(of: summary), let pullRequest = knownPullRequest(of: branch) else { return nil }
        let isLocal = branch.host == nil
        var items: [SidebarTaskMenu.Item] = []
        if isLocal {
            items.append(
                SidebarTaskMenu.Item(title: "Open in Native", spokenTitle: "Open Pull Request in Native") {
                    gitHub.openInNative(pullRequest)
                })
        }
        items += [
            SidebarTaskMenu.Item(title: "Open on GitHub", spokenTitle: "Open Pull Request on GitHub") {
                gitHub.openInBrowser(pullRequest)
            },
            SidebarTaskMenu.Item(title: "Copy Link", spokenTitle: "Copy Pull Request Link") {
                gitHub.copyURL(pullRequest)
            },
        ]
        if isLocal, gitHub.offersMerge(pullRequest) {
            items.append(
                SidebarTaskMenu.Item(title: "Merge…", spokenTitle: "Merge Pull Request…") {
                    gitHub.requestMerge(pullRequest)
                })
        }
        return SidebarTaskMenu(title: "Pull Request", spokenSummary: pullRequest.spokenSummary, items: items)
    }

    /// What gh last said about a branch. Asking about a paired host starts its first lookup, as
    /// `GitStore.model(for:)` starts reading a checkout; `GitHubModel`'s refreshes take it from there.
    private func knownPullRequest(of branch: BranchReference) -> PullRequestSummary? {
        let found = gitHub.branchPullRequest(for: branch)
        if branch.host != nil, found == nil || found?.fetchedAt == .distantPast,
            gitHub.branchLookupsInFlight[branch] == nil
        {
            Task { await gitHub.loadPullRequest(for: branch) }
        }
        return found?.pullRequest
    }

    private func branch(of key: SessionKey, project: Project.ID, cwd: String) -> BranchReference? {
        guard let folder = checkout(of: key, project: project, cwd: cwd) else { return nil }
        if let archived = archivedBranch(of: key, project: project, folder: folder) { return archived }
        let repository = git.model(for: folder, session: key)
        guard let name = repository.branch?.name else { return nil }
        if repository.isLocal { return BranchReference(directory: folder, branch: name) }
        // Without its host, a paired host's checkout has no gh to ask: never this Mac's instead.
        guard let host = model.device(of: key).remoteHostID else { return nil }
        return BranchReference(host: host, directory: folder, branch: name)
    }

    private func archivedBranch(of key: SessionKey, project: Project.ID, folder: URL) -> BranchReference? {
        guard model.isArchived(key), let root = projectCheckout(for: key, in: project),
            let name = git.archivedTaskBranch(at: folder, of: root, session: key)
        else { return nil }
        return BranchReference(host: model.device(of: key).remoteHostID, directory: root, branch: name)
    }

    private func projectCheckout(for key: SessionKey, in id: Project.ID) -> URL? {
        model.projects.project(id)?.checkoutPath(on: model.device(of: key)).map {
            URL(filePath: $0, directoryHint: .isDirectory)
        }
    }

    /// The task's folder, unless it's the project's checkout on the task's machine.
    private func checkout(of key: SessionKey, project id: Project.ID, cwd: String) -> URL? {
        guard let project = model.projects.project(id) else { return nil }
        if let shared = project.checkoutPath(on: model.device(of: key)), SessionFolder.isSame(cwd, shared) {
            return nil
        }
        return URL(filePath: cwd, directoryHint: .isDirectory)
    }
}
