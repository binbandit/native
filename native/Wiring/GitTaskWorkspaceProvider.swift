import ACP
import AIInstructions
import Foundation
import Git
import GitHub
import TaskScripts

/// Gives AppModel's tasks their workspaces from the Git feature: a worktree or branch per task as
/// the Git settings say, named with the GitHub username prefix, and put away (with a checkpoint)
/// when the task is archived. Only worktrees Native made are ever removed. The task scripts run
/// around them: setup and teardown through GitStore's hooks, task-deleted from here.
final class GitTaskWorkspaceProvider: TaskWorkspaceProvider {
    private let git: GitStore
    private let gitHub: GitHubModel
    private let scripts: TaskScriptCenter
    /// Each project's last verdicts on removed workspaces, kept while its branches stay put.
    private var removedVerdicts: [URL: RemovedVerdicts] = [:]

    init(git: GitStore, gitHub: GitHubModel, scripts: TaskScriptCenter) {
        self.git = git
        self.gitHub = gitHub
        self.scripts = scripts
    }

    func workspace(forNewTaskIn project: Project, title: String?) async throws -> URL {
        let prefix = git.settings.branchPrefix(forProjectAt: project.url, gitHubLogin: await gitHubLogin(for: project))
        return try await git.prepareTaskCheckout(in: project.url, prefix: prefix)?.folder ?? project.url
    }

    func newTaskWorkspaceLabel(in project: Project) -> String {
        switch git.settings.newTaskWorkspace(forProjectAt: project.url) {
        case .worktree: "Creating a worktree"
        case .branch: "Creating a branch"
        }
    }

    func archiveWorkspace(at folder: URL, in project: Project) async throws -> String? {
        guard await git.isTaskWorktree(folder, of: project.url) else { return nil }
        let removed = try await git.removeTaskWorktree(at: folder, keepingRecord: true)
        var summary = removed.summary
        if let failure = scripts.teardownFailure(in: folder) {
            // Teardown never stops archiving, but the user hears it didn't work where they archived.
            summary += " Its teardown script \(failure.result.outcome.phrase)."
        }
        return summary
    }

    func restoreWorkspace(at folder: URL, in project: Project, task: ArchivedTaskDetails?) async throws -> Bool {
        let archived: ArchivedWorktree
        if let recorded = try await git.archivedTaskWorktree(at: folder, of: project.url) {
            archived = recorded
        } else if let task,
            let rebuilt = try await git.rebuildArchivedTaskWorktree(
                at: folder, of: project.url, title: task.title, archivedAt: task.archivedAt)
        {
            // Archived before archives were recorded: worked out from what that archive left in git.
            switch rebuilt {
            case .found(let found):
                archived = found
            case .noBranch(let checkpoint):
                throw TaskWorkspaceRestoreFailure.branchNotFound(checkpoint: checkpoint?.reference)
            case .ambiguous(let names, let checkpoint):
                throw TaskWorkspaceRestoreFailure.branchAmbiguous(names, checkpoint: checkpoint?.reference)
            }
        } else {
            return false
        }
        _ = try await git.restoreArchivedTaskWorktree(archived, of: project.url)
        // Views asked about the folder while it was gone; they show its branch and changes again.
        git.refresh(folder: folder)
        return true
    }

    func archivedWorkspaceFolders(of project: Project) async -> [URL] {
        (try? await git.archivedTaskWorktrees(of: project.url))?.map(\.path) ?? []
    }

    func removedWorkspaces(
        among tasks: [(folder: URL, title: String)], in project: Project
    ) async -> [URL: RemovedWorkspace.Fate] {
        let removed = await git.removedTaskFolders(among: tasks.map(\.folder), of: project.url)
        // What was put away by archiving comes back by unarchiving, not here.
        let archived = await archivedWorkspaceFolders(of: project)
        let candidates = tasks.filter { task in
            removed.contains(task.folder)
                && !archived.contains { SessionFolder.isSame($0.folderPath, task.folder.folderPath) }
        }
        guard !candidates.isEmpty else { return [:] }
        // Judging asks GitHub and reads every branch; the same branches give the same answers,
        // except a pull request merged on GitHub since, which a while later catches.
        let fingerprint = await git.refsFingerprint(of: project.url)
        if let cached = removedVerdicts[project.url], cached.fingerprint == fingerprint,
            cached.judgedAt.timeIntervalSinceNow > -Self.verdictLifetime,
            candidates.allSatisfy({ cached.fates[$0.folder] != nil })
        {
            return cached.fates.filter { folder, _ in candidates.contains { $0.folder == folder } }
        }
        let prefix = git.settings.branchPrefix(forProjectAt: project.url, gitHubLogin: await gitHubLogin(for: project))
        let gitHub = gitHub
        let root = project.url
        guard
            let verdicts = try? await git.removedTaskWorktreeVerdicts(
                candidates.map { RemovedWorktreeTask(path: $0.folder, title: $0.title) }, of: root,
                branchPrefix: prefix,
                pullRequests: { queries in
                    await GitCleanupWiring.mergedPullRequests(queries, in: root, cli: await gitHub.cli())
                })
        else { return [:] }
        var fates: [URL: RemovedWorkspace.Fate] = [:]
        for (task, verdict) in zip(candidates, verdicts) {
            fates[task.folder] = Self.fate(of: verdict)
        }
        removedVerdicts[project.url] = RemovedVerdicts(fingerprint: fingerprint, judgedAt: .now, fates: fates)
        return fates
    }

    private static let verdictLifetime: TimeInterval = 10 * 60

    func restoreRemovedWorkspace(at folder: URL, branch: String, in project: Project) async throws {
        _ = try await git.restoreRemovedTaskWorktree(at: folder, branch: branch, of: project.url)
        git.refresh(folder: folder)
    }

    /// A verdict in the words the task and the archive toast use.
    private static func fate(of verdict: RemovedWorktreeVerdict) -> RemovedWorkspace.Fate {
        switch verdict {
        case .done(.merged(_, .pullRequest(let number, _, _))):
            .done(reason: "its branch was merged in pull request #\(number)")
        case .done(.merged(_, .ancestry(let base))), .done(.merged(_, .sameContent(let base))):
            .done(reason: "its work is in \(base)")
        case .done(.noCommits):
            .done(reason: "its branch had no commits of its own")
        case .done(.branchGone):
            .done(reason: "its branch is gone")
        case .unmerged(let branch, .unmergedCommits(let count)):
            .kept(
                RemovedWorkspace(
                    branch: branch,
                    detail: count == 1
                        ? "\(branch) has 1 commit that isn't merged."
                        : "\(branch) has \(count) commits that aren't merged."))
        case .unmerged(let branch, .changedSincePullRequest(let number)):
            .kept(
                RemovedWorkspace(
                    branch: branch, detail: "\(branch) has commits since pull request #\(number) was merged."))
        case .unmerged(let branch, _):
            .kept(RemovedWorkspace(branch: branch, detail: "Its branch, \(branch), is still there."))
        case .unknownBranch(let names):
            .kept(
                RemovedWorkspace(
                    branch: nil,
                    detail: "Native can't tell which branch it was on: \(names.joined(separator: ", "))."))
        }
    }

    func deleteWorkspace(at folder: URL, in project: Project) async throws {
        try await git.forgetArchivedTaskWorktree(at: folder, of: project.url)
        guard await git.isTaskWorktree(folder, of: project.url) else { return }
        _ = try await git.removeTaskWorktree(at: folder)
    }

    func deleteWorkspaces(of project: Project) async throws {
        for folder in await git.taskWorktrees(of: project.url) {
            _ = try await git.removeTaskWorktree(at: folder)
        }
        try await git.forgetArchivedTaskWorktrees(of: project.url)
    }

    func taskFolders(of project: Project) async -> [URL] {
        await git.taskWorktrees(of: project.url)
    }

    func taskWasDeleted(_ task: SessionKey, title: String, folder: URL, in project: Project) async {
        let main = await git.checkout(of: project.url)?.main ?? project.url
        scripts.taskDeleted(
            folder: folder, projectRoot: main,
            task: TaskScriptTask(id: task.id.rawValue, title: title, agent: task.agent.rawValue))
    }

    /// Renames the task's provisional branch after its title, unless it was pushed or renamed. With
    /// the user's instructions for branch names, the on-device model names it, following them.
    func taskDidGetTitle(_ title: String, request: String?, workspace: URL, in project: Project) async {
        guard let instructions = AIInstructionsStore.shared.addition(for: .branchName, in: project.url) else {
            await git.renameProvisionalBranch(at: workspace, title: title)
            return
        }
        await git.renameProvisionalBranch(at: workspace, title: title) { title, prefix in
            try? await BranchNameDrafter.suggest(
                title: title, request: request, prefix: prefix, instructions: instructions)
        }
    }

    /// The signed-in GitHub user, only asked for when the prefix needs it.
    private func gitHubLogin(for project: Project) async -> String? {
        guard git.settings.branchPrefixMode(forProjectAt: project.url) == .gitHubUsername else { return nil }
        if let login = gitHub.currentLogin { return login }
        return try? await gitHub.cli().currentUser().login
    }
}

/// A project's verdicts on removed workspaces, and the branches they were made from.
private struct RemovedVerdicts {
    let fingerprint: String?
    let judgedAt: Date
    let fates: [URL: RemovedWorkspace.Fate]
}
