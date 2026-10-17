import Foundation

/// Where tasks run and what happens to that place when they go away. The Git feature provides it
/// (a worktree or branch per task, set up from the project's settings); without one, tasks run in
/// the project folder and nothing is removed.
protocol TaskWorkspaceProvider: AnyObject {
    /// The folder a new task in `project` should run in: the project itself, or one made for it.
    func workspace(forNewTaskIn project: Project, title: String?) async throws -> URL

    /// Puts away what Native made for a task leaving the sidebar (archive). Returns how to bring it
    /// back, or nil when there was nothing of Native's to put away. Never touches the user's own
    /// project folder.
    func archiveWorkspace(at folder: URL, in project: Project) async throws -> TaskWorkspaceRemoval?

    /// Removes what Native made for a task for good (delete), saving a checkpoint of uncommitted
    /// work first. Never touches the user's own project folder.
    func deleteWorkspace(at folder: URL, in project: Project) async throws

    /// Removes everything Native made for a project's tasks, for when the project is deleted.
    func deleteWorkspaces(of project: Project) async throws

    /// The folders Native made for the project's tasks (worktrees), so their sessions are listed
    /// with the project's own.
    func taskFolders(of project: Project) async -> [URL]
}

/// A task's workspace that was put away, and how to restore it.
struct TaskWorkspaceRemoval {
    /// What was done, in a sentence: "Removed the worktree; uncommitted work saved as a checkpoint."
    let summary: String
    let restore: () async throws -> Void
}
