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

    func archiveWorkspace(at folder: URL, in project: Project) async throws -> TaskWorkspaceRemoval? {
        guard await git.isTaskWorktree(folder, of: project.url) else { return nil }
        let removed = try await git.removeTaskWorktree(at: folder)
        var summary = removed.summary
        if let failure = scripts.teardownFailure(in: folder) {
            // Teardown never stops archiving, but the user hears it didn't work where they archived.
            summary +=
                " Its teardown script \(failure.result.outcome.phrase); Scripts in the status bar has its output."
        }
        return TaskWorkspaceRemoval(summary: summary) { [git] in
            _ = try await git.restoreTaskWorktree(removed)
        }
    }

    func deleteWorkspace(at folder: URL, in project: Project) async throws {
        guard await git.isTaskWorktree(folder, of: project.url) else { return }
        _ = try await git.removeTaskWorktree(at: folder)
    }

    func deleteWorkspaces(of project: Project) async throws {
        for folder in await git.taskWorktrees(of: project.url) {
            _ = try await git.removeTaskWorktree(at: folder)
        }
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
