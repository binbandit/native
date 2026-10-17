import Foundation

/// A snapshot of a working tree's uncommitted state, saved as a commit under
/// `refs/native-checkpoints/` so removing a worktree never loses work. Restore one with
/// `git checkout <reference> -- .` or `git stash apply <commit>`-style tools.
public struct Checkpoint: Hashable, Sendable {
    public var reference: String
    public var commit: String
}
