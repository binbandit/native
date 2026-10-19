import Foundation
import Git

/// Clean Up Merged's git work for a project: finding what's merged, and the steps that aren't part
/// of archiving a task (which removes worktrees through the archive path, teardown and all).
extension GitStore {
    /// What cleaning up the project's merged work would do. `pullRequests` answers for the branches
    /// that were pushed, or says why GitHub couldn't be asked.
    func mergedCleanupPlan(
        in project: URL, branchPrefix: String,
        pullRequests: @escaping @Sendable ([CleanupPullRequestLookup.Query]) async -> CleanupPullRequestLookup
    ) async throws -> MergedCleanupPlan {
        let repository = try await requireRepository(at: project)
        let options = MergedCleanupOptions(taskLocation: Self.taskLocation(of: repository), branchPrefix: branchPrefix)
        return try await repository.mergedCleanupPlan(options, pullRequests: pullRequests)
    }

    /// Deletes a merged branch, keeping its tip and config so `restoreDeletedBranch` can bring it
    /// back (and Unarchive, for a task whose worktree had it).
    func deleteMergedBranch(_ branch: String, in project: URL) async throws {
        try await requireRepository(at: project).archiveBranch(branch)
        refresh(folder: project)
    }

    func restoreDeletedBranch(_ branch: String, in project: URL) async throws {
        try await requireRepository(at: project).restoreArchivedBranch(branch)
        refresh(folder: project)
    }

    func hasBranch(_ branch: String, in project: URL) async -> Bool {
        (try? await requireRepository(at: project).hasBranch(branch)) == true
    }

    /// Forgets a worktree record whose folder is gone.
    func forgetStaleWorktree(at path: URL, in project: URL) async throws {
        try await requireRepository(at: project).forgetStaleWorktree(at: path)
    }
}
