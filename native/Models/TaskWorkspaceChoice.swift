import Foundation

/// A task's working folder, chosen before its first message.
enum TaskWorkspaceChoice: Hashable, Codable {
    case project
    case newWorktree
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
