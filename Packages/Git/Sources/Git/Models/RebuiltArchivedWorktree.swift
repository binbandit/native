import Foundation

/// What `Repository.rebuildArchivedWorktree` could work out about a task worktree archived before
/// Native recorded what brings one back.
public enum RebuiltArchivedWorktree: Hashable, Sendable {
    /// Everything needed to restore it, as a record would have had it.
    case found(ArchivedWorktree)
    /// No branch, kept or deleted with a copy, could have been the one it was on.
    case noBranch
    /// More than one branch could have been the one it was on, by name; Native doesn't guess.
    case ambiguous([String])
}
