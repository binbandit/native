import ACP
import Foundation
import Git

/// Task worktrees put away when their tasks were archived. What brings one back (its folder, branch
/// and checkpoint) is recorded in the repository before anything is removed
/// (`Repository.recordArchivedWorktree`), not kept in Native's memory, so unarchiving works after a
/// relaunch, and after Native quits partway through archiving or restoring.
extension GitStore {
    /// The task worktrees put away in the repository at `project`, by folder.
    func archivedTaskWorktrees(of project: URL) async throws -> [ArchivedWorktree] {
        guard let repository = try await resolveGit().repository(at: project) else { return [] }
        return try await repository.archivedWorktrees()
    }

    /// The task worktree put away at `folder`, whichever spelling each path uses (`/tmp/x` and
    /// `/private/tmp/x`), as a session's folder may differ from git's.
    func archivedTaskWorktree(at folder: URL, of project: URL) async throws -> ArchivedWorktree? {
        try await archivedTaskWorktrees(of: project).first {
            SessionFolder.isSame($0.path.folderPath, folder.folderPath)
        }
    }

    /// Brings a task worktree back where it was, on its branch with its uncommitted work, then sets
    /// it up the way a new task's is (env files, setup scripts), since teardown ran when it went.
    func restoreArchivedTaskWorktree(_ archived: ArchivedWorktree, of project: URL) async throws -> URL {
        let repository = try await requireRepository(at: project)
        let worktree = try await repository.restoreArchivedWorktree(archived)
        return try await setUp(worktree, of: repository, branch: archived.branch).folder
    }

    /// Works out what brings back a task worktree archived before Native recorded archives, from
    /// its checkpoint and branch (`Repository.rebuildArchivedWorktree`). `nil` unless `folder` is
    /// where Native puts the project's task worktrees and isn't one now.
    func rebuildArchivedTaskWorktree(
        at folder: URL, of project: URL, title: String?, archivedAt: Date?
    ) async throws -> RebuiltArchivedWorktree? {
        guard let repository = try await resolveGit().repository(at: project) else { return nil }
        let location = taskLocation(of: repository).folderPath
        guard SessionFolder.contains(location, folder.folderPath), !SessionFolder.isSame(location, folder.folderPath),
            await !isTaskWorktree(folder, of: project)
        else { return nil }
        return try await repository.rebuildArchivedWorktree(
            at: folder, title: title, archivedAt: archivedAt, isSameFolder: SessionFolder.isSame)
    }

    /// Forgets what was put away at `folder`, for a task deleted while archived.
    func forgetArchivedTaskWorktree(at folder: URL, of project: URL) async throws {
        guard let repository = try await resolveGit().repository(at: project),
            let archived = try await archivedTaskWorktree(at: folder, of: project)
        else { return }
        try await repository.forgetArchivedWorktree(at: archived.path)
    }

    /// Forgets every task worktree put away in the project, for when the project is deleted.
    func forgetArchivedTaskWorktrees(of project: URL) async throws {
        guard let repository = try await resolveGit().repository(at: project) else { return }
        for archived in try await repository.archivedWorktrees() {
            try await repository.forgetArchivedWorktree(at: archived.path)
        }
    }
}
