import Foundation

/// A checkout just made for a task. A receipt grants cleanup of this exact checkout only;
/// a branch that moved or a folder with any user files must stay on disk.
public struct UnusedTaskWorktree: Sendable {
    public let path: URL
    public let branch: String
    public let commit: String

    public init?(worktree: Worktree) {
        guard !worktree.isMain, let branch = worktree.branch, let commit = worktree.head else { return nil }
        path = worktree.path
        self.branch = branch
        self.commit = commit
    }
}
