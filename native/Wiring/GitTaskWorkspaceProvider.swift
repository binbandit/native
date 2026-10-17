import Foundation
import Git
import GitHub

/// Gives AppModel's tasks their workspaces from the Git feature: a worktree or branch per task as
/// the Git settings say, named with the GitHub username prefix, and put away (with a checkpoint)
/// when the task is archived. Only worktrees Native made are ever removed.
final class GitTaskWorkspaceProvider: TaskWorkspaceProvider {
    private let git: GitStore
    private let gitHub: GitHubModel

    init(git: GitStore, gitHub: GitHubModel) {
        self.git = git
        self.gitHub = gitHub
    }

    func workspace(forNewTaskIn project: Project, title: String?) async throws -> URL {
        let prefix = git.settings.branchPrefix(gitHubLogin: await gitHubLogin())
        return try await git.prepareTaskCheckout(in: project.url, prefix: prefix)?.folder ?? project.url
    }

    func archiveWorkspace(at folder: URL, in project: Project) async throws -> TaskWorkspaceRemoval? {
        guard await git.isTaskWorktree(folder, of: project.url) else { return nil }
        let removed = try await git.removeTaskWorktree(at: folder)
        return TaskWorkspaceRemoval(summary: removed.summary) { [git] in
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

    /// Renames the task's provisional branch after its title, unless it was pushed or renamed.
    func taskDidGetTitle(_ title: String, workspace: URL, in project: Project) async {
        await git.renameProvisionalBranch(at: workspace, title: title)
    }

    /// The signed-in GitHub user, only asked for when the prefix needs it.
    private func gitHubLogin() async -> String? {
        guard git.settings.branchPrefixMode == .gitHubUsername else { return nil }
        if let login = gitHub.currentLogin { return login }
        return try? await gitHub.cli().currentUser().login
    }
}
