import Foundation
import Git

/// What removing a task's worktree left behind, so the removal can be described and undone.
struct RemovedTaskWorktree: Hashable, Sendable {
    let path: URL
    /// The repository's main working tree, which restores it.
    let mainRoot: URL
    /// The branch the worktree had checked out; `nil` when it was detached.
    let branch: String?
    /// Uncommitted work saved before removal; `nil` when there was none.
    let checkpoint: Checkpoint?

    /// "Removed the worktree. Uncommitted work was saved as a checkpoint." for the archive UI.
    var summary: String {
        checkpoint == nil
            ? "Removed the worktree. Its branch \(branch ?? "") keeps every commit."
            : "Removed the worktree. Uncommitted work was saved as a checkpoint, so it can be restored."
    }
}
