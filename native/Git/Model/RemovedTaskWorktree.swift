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
    /// The branch was deleted too (kept under `refs/native-archived-branches/`).
    let archivedBranch: Bool

    /// "Removed the worktree. Uncommitted work was saved as a checkpoint." for the archive UI.
    var summary: String {
        let work = checkpoint == nil ? "" : " Uncommitted work was saved as a checkpoint."
        let branchNote = archivedBranch ? " The branch was deleted; restoring brings it back." : ""
        return "Removed the worktree.\(work)\(branchNote) You can restore it."
    }
}
