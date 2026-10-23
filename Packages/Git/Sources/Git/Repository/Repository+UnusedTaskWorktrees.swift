import Foundation

extension Repository {
    /// Removes an unused checkout only if it still matches its creation receipt. No force,
    /// checkpoint or branch deletion: a branch may have been chosen from existing work.
    /// Ignored files count as work too, including files produced by setup commands.
    @discardableResult
    public func removeUnusedTaskWorktree(_ receipt: UnusedTaskWorktree) async throws(GitError) -> Bool {
        guard let worktree = await listedWorktree(at: receipt.path, in: try await worktrees()),
            !worktree.isMain, !worktree.isLocked, !worktree.isPrunable,
            worktree.branch == receipt.branch, worktree.head == receipt.commit,
            let checkout = try await git.repository(at: worktree.path)
        else { return false }
        let status = try await checkout.run(
            ["status", "--porcelain=v1", "--untracked-files=all", "--ignored"], readOnly: true)
        guard status.stdout.isEmpty else { return false }
        try await removeWorktree(at: worktree.path, checkpoint: false)
        return true
    }
}
