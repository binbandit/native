import Foundation

/// Where tasks run and what happens to that place when they go away. The Git feature provides it
/// (a worktree or branch per task, set up from the project's settings); without one, tasks run in
/// the project folder and nothing is removed.
protocol TaskWorkspaceProvider: AnyObject {
    /// The folder a new task in `project` should run in: the project itself, or one made for it.
    func workspace(forNewTaskIn project: Project, title: String?) async throws -> URL

    /// What `workspace(forNewTaskIn:title:)` makes, as the step a starting task shows while it
    /// runs: "Creating a worktree", "Creating a branch".
    func newTaskWorkspaceLabel(in project: Project) -> String

    /// Puts away what Native made for a task leaving the sidebar (archive), keeping what
    /// `restoreWorkspace` needs with the project itself, so it can come back in a later run of
    /// Native too. Returns what was done as a sentence for the archive's toast ("Removed its
    /// worktree, saving uncommitted work as a checkpoint."), or nil when there was nothing of
    /// Native's to put away. Never touches the user's own project folder.
    func archiveWorkspace(at folder: URL, in project: Project) async throws -> String?

    /// Brings back what `archiveWorkspace` put away at `folder`, picking up where an archive or
    /// restore that Native quit during stopped. Returns whether there was anything to bring back.
    @discardableResult
    func restoreWorkspace(at folder: URL, in project: Project) async throws -> Bool

    /// The folders `archiveWorkspace` put away in `project` that haven't been brought back.
    func archivedWorkspaceFolders(of project: Project) async -> [URL]

    /// Removes what Native made for a task for good (delete), saving a checkpoint of uncommitted
    /// work first, or forgets what it put away if the task was archived. Never touches the user's
    /// own project folder.
    func deleteWorkspace(at folder: URL, in project: Project) async throws

    /// Removes everything Native made for a project's tasks, for when the project is deleted.
    func deleteWorkspaces(of project: Project) async throws

    /// Called once, when a task gets its first real title (generated or the user's), so a
    /// provisional branch can be renamed after it. `request` is the task's first message, for names
    /// that need more than the title (a ticket key). `workspace` is the task's folder, which is the
    /// project's own in branch mode; the provider decides whether there's a branch to rename.
    func taskDidGetTitle(_ title: String, request: String?, workspace: URL, in project: Project) async

    /// The folders Native made for the project's tasks (worktrees), so their sessions are listed
    /// with the project's own.
    func taskFolders(of project: Project) async -> [URL]

    /// Called once a task is deleted for good, after what Native made for it is gone, so whatever
    /// cleans up after tasks (the user's scripts) can. `folder` is where it ran.
    func taskWasDeleted(_ task: SessionKey, title: String, folder: URL, in project: Project) async
}

extension TaskWorkspaceProvider {
    func taskWasDeleted(_ task: SessionKey, title: String, folder: URL, in project: Project) async {}
}
