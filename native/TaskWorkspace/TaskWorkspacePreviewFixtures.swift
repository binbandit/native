#if DEBUG
import SwiftUI

enum TaskWorkspacePreviewFixtures {
    static let options = [
        TaskWorkspaceOption(choice: .project, title: "Project Folder", detail: "sample", isCurrent: false),
        TaskWorkspaceOption(
            choice: .newWorktree, title: "New Worktree", detail: "A new branch in its own folder", isCurrent: false),
        TaskWorkspaceOption(choice: .branch("main"), title: "main", detail: "sample", isCurrent: false),
        TaskWorkspaceOption(
            choice: .branch("fix/long-branch-name-for-the-task"), title: "fix/long-branch-name-for-the-task",
            detail: "worktrees/sample/task", isCurrent: true),
    ]

    static func context(editable: Bool) -> NewSessionContext {
        NewSessionContext(
            projectName: "Sample", projectIcon: .initial,
            workspace: .worktree(branch: "fix/long-branch-name-for-the-task", base: "main"),
            checkoutChanges: 0, tasks: [], pullRequests: [], actions: [], draft: { _ in }, editActions: {},
            changeWorkspace: editable ? {} : nil, chooseWorkspace: editable ? { _ in } : nil)
    }
}
#endif
