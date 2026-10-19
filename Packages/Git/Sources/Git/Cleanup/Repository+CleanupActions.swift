import Foundation

// What acting on a `MergedCleanupPlan` takes that git doesn't already offer one by one. Worktrees
// go through `removeWorktree` (via the app's archive path, which checkpoints them) and branches
// through `archiveBranch`, so both can come back.
extension Repository {
    /// Forgets one worktree whose folder is gone, as `git worktree prune` would, leaving the other
    /// stale records alone.
    public func forgetStaleWorktree(at path: URL) async throws(GitError) {
        guard let worktree = try await worktrees().first(where: { Self.cleanupSpelling(of: $0.path) == Self.cleanupSpelling(of: path) }),
            worktree.isPrunable
        else {
            throw .failed(
                arguments: ["worktree", "remove"], status: 128,
                stderr: "\(path.path(percentEncoded: false)) isn't a worktree record whose folder is gone.")
        }
        // git matches the path as it spelled it, without a trailing slash.
        try await run(["worktree", "remove", "--", Self.cleanupSpelling(of: worktree.path)])
    }
}
