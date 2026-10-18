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

    /// "Removed its worktree, saving uncommitted work as a checkpoint." for the archive toast, whose
    /// Undo restores all of it, so the sentence doesn't need to say so.
    var summary: String {
        let removed = archivedBranch ? "Removed its worktree and branch" : "Removed its worktree"
        return checkpoint == nil ? "\(removed)." : "\(removed), saving uncommitted work as a checkpoint."
    }
}
