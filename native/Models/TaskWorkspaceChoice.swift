import Foundation

/// A task's working folder, chosen before its first message.
enum TaskWorkspaceChoice: Hashable, Codable {
    case project
    case newWorktree
    /// A new worktree from a commit chosen ahead (`TaskWorkspaceProvider.newWorktreeStart`), so
    /// tasks given one brief start from identical code. `notice` says why it's a local commit.
    case newWorktreeFrom(commit: String, branch: String?, notice: String?)
    case branch(String)
    case worktree(URL)
}

struct TaskWorkspaceOption: Identifiable {
    let choice: TaskWorkspaceChoice
    let title: String
    let detail: String
    let isCurrent: Bool

    var id: TaskWorkspaceChoice { choice }
}
