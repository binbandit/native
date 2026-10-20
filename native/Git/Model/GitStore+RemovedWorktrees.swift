import ACP
import Foundation
import Git

/// Task worktrees removed by something other than Native (`git worktree remove`, `rm -rf`, a prune,
/// another tool), which leave their tasks listed in folders that are gone.
extension GitStore {
    /// Which of `folders` were task worktrees of the repository at `project` and aren't any more:
    /// inside Native's worktree location, with no worktree at or above them (git's record of one
    /// whose folder was deleted doesn't count).
    func removedTaskFolders(among folders: [URL], of project: URL) async -> [URL] {
        guard let repository = try? await resolveGit().repository(at: project),
            let worktrees = try? await repository.worktrees()
        else { return [] }
        let location = Self.taskLocation(of: repository).folderPath
        let live = worktrees.filter { !$0.isPrunable }.map(\.path.folderPath)
        return folders.filter { folder in
            SessionFolder.contains(location, folder.folderPath) && !SessionFolder.isSame(location, folder.folderPath)
                && !live.contains { SessionFolder.contains($0, folder.folderPath) }
        }
    }

    /// What each task whose worktree was removed should become (`Repository.removedWorktreeVerdicts`).
    func removedTaskWorktreeVerdicts(
        _ tasks: [RemovedWorktreeTask], of project: URL, branchPrefix: String,
        pullRequests: @escaping @Sendable ([CleanupPullRequestLookup.Query]) async -> CleanupPullRequestLookup
    ) async throws -> [RemovedWorktreeVerdict] {
        let repository = try await requireRepository(at: project)
        let options = MergedCleanupOptions(taskLocation: Self.taskLocation(of: repository), branchPrefix: branchPrefix)
        return try await repository.removedWorktreeVerdicts(for: tasks, options: options, pullRequests: pullRequests)
    }

    /// Checks `branch` out at `folder` again, set up like a new task's worktree. Whatever was
    /// uncommitted when it was removed is gone: nothing outside Native saved it.
    func restoreRemovedTaskWorktree(at folder: URL, branch: String, of project: URL) async throws -> URL {
        try await restoreArchivedTaskWorktree(
            ArchivedWorktree(path: folder, branch: branch, checkpoint: nil), of: project)
    }
}
