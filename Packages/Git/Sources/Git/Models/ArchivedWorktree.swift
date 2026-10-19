import Foundation

/// A task worktree Native removed and can put back: where it was, the branch it had checked out,
/// and the checkpoint of its uncommitted work. Kept in the repository's own config
/// (`Repository.recordArchivedWorktree`), so it outlives Native quitting, and read back from there.
public struct ArchivedWorktree: Hashable, Sendable {
    public var path: URL
    public var branch: String
    /// Uncommitted work saved before removal; `nil` when there was none, or its ref was deleted since.
    public var checkpoint: Checkpoint?

    public init(path: URL, branch: String, checkpoint: Checkpoint?) {
        self.path = path
        self.branch = branch
        self.checkpoint = checkpoint
    }
}
