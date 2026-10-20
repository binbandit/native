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
        let paths = folders.map(\.folderPath)
        let removed = await Self.removed(
            paths, location: taskLocation(of: repository).folderPath,
            live: worktrees.filter { !$0.isPrunable }.map(\.path.folderPath))
        return folders.indices.filter { removed.contains($0) }.map { folders[$0] }
    }

    /// The indices of `paths` inside `location` but in none of `live`. Off the main thread, since
    /// comparing spellings (`/tmp`, `/private/tmp`) reads the disk, once per path.
    @concurrent
    private nonisolated static func removed(_ paths: [String], location: String, live: [String]) async -> Set<Int> {
        func resolved(_ path: String) -> String { SessionFolder.listingPaths(for: path).last ?? path }
        let location = resolved(location)
        let live = live.map(resolved)
        var removed: Set<Int> = []
        for (index, path) in paths.enumerated() {
            let path = resolved(path)
            guard path.hasPrefix(location + "/"), !live.contains(where: { path == $0 || path.hasPrefix($0 + "/") })
            else { continue }
            removed.insert(index)
        }
        return removed
    }

    /// Where the repository's branches point (`Repository.refsFingerprint`), to tell whether verdicts
    /// still hold.
    func refsFingerprint(of project: URL) async -> String? {
        try? await requireRepository(at: project).refsFingerprint()
    }

    /// What each task whose worktree was removed should become (`Repository.removedWorktreeVerdicts`).
    func removedTaskWorktreeVerdicts(
        _ tasks: [RemovedWorktreeTask], of project: URL, branchPrefix: String,
        pullRequests: @escaping @Sendable ([CleanupPullRequestLookup.Query]) async -> CleanupPullRequestLookup
    ) async throws -> [RemovedWorktreeVerdict] {
        let repository = try await requireRepository(at: project)
        let options = MergedCleanupOptions(taskLocation: taskLocation(of: repository), branchPrefix: branchPrefix)
        return try await repository.removedWorktreeVerdicts(for: tasks, options: options, pullRequests: pullRequests)
    }

    /// Checks `branch` out at `folder` again, set up like a new task's worktree. Whatever was
    /// uncommitted when it was removed is gone: nothing outside Native saved it.
    func restoreRemovedTaskWorktree(at folder: URL, branch: String, of project: URL) async throws -> URL {
        try await restoreArchivedTaskWorktree(
            ArchivedWorktree(path: folder, branch: branch, checkpoint: nil), of: project)
    }
}
