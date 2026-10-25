import Foundation

/// Where tasks run and what happens to that place when they go away. The Git feature provides it
/// (a worktree or branch per task, set up from the project's settings); without one, tasks run in
/// the project folder and nothing is removed.
protocol TaskWorkspaceProvider: AnyObject {
    func workspaceOptions(in project: Project, current: URL) async throws -> [TaskWorkspaceOption]
    func workspace(for choice: TaskWorkspaceChoice, in project: Project) async throws -> URL
    func prepareWorkspace(for choice: TaskWorkspaceChoice, in project: Project) async throws -> TaskWorkspacePreparation
    /// Removes only an untouched checkout created for a task, never a user-owned folder.
    func removeUnusedWorkspace(at folder: URL, in project: Project) async throws -> Bool

    /// Where a new worktree in `project` would start now (fetching first, as the Git settings and
    /// policy allow), as a choice that makes one there: several tasks prepared with it start from
    /// the same commit. Nil where tasks don't get worktrees.
    func newWorktreeStart(in project: Project) async throws -> TaskWorkspaceChoice?

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

    /// Brings back what `archiveWorkspace` put away at `folder`, in this run of Native or a later
    /// one, picking up where an archive or restore Native quit during stopped. With `task`, a
    /// workspace archived before that was recorded is rebuilt from what the archive left, or
    /// `TaskWorkspaceRestoreFailure` says what's missing. Returns whether there was anything to
    /// bring back.
    @discardableResult
    func restoreWorkspace(at folder: URL, in project: Project, task: ArchivedTaskDetails?) async throws -> Bool

    /// The folders `archiveWorkspace` put away in `project` that haven't been brought back.
    func archivedWorkspaceFolders(of project: Project) async -> [URL]

    /// What should become of the tasks among `tasks` whose workspaces were removed outside Native,
    /// by folder: done (archive them) or kept in sight. Folders that still have their workspace, or
    /// that Native never made one in, are left out. Changes nothing.
    func removedWorkspaces(
        among tasks: [(folder: URL, title: String)], in project: Project
    ) async -> [URL: RemovedWorkspace.Fate]

    /// Makes a removed workspace again at `folder`, on `branch`, set up like a new task's.
    func restoreRemovedWorkspace(at folder: URL, branch: String, in project: Project) async throws

    /// Removes what Native made for a task for good (delete), saving a checkpoint of uncommitted
    /// work first, or forgets what was put away for it if it's archived. Never touches the user's
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

    func newWorktreeStart(in project: Project) async throws -> TaskWorkspaceChoice? { nil }

    /// Brings back only what was recorded, for workspaces no task was archived with.
    @discardableResult
    func restoreWorkspace(at folder: URL, in project: Project) async throws -> Bool {
        try await restoreWorkspace(at: folder, in: project, task: nil)
    }
}

/// What Native knows about an archived task that helps rebuild its workspace when nothing was
/// recorded: its title, and when it was archived, which tells that archive's checkpoint from
/// earlier ones.
struct ArchivedTaskDetails: Hashable, Sendable {
    let title: String
    let archivedAt: Date?
}

/// Why a new task's workspace couldn't be made, when the user can do something about it.
enum TaskWorkspaceError: LocalizedError {
    /// The project is a repository without commits, so there's nothing to branch a worktree from.
    case noCommits

    var errorDescription: String? {
        switch self {
        case .noCommits: "This repository has no commits yet, so there's nothing to branch a worktree from."
        }
    }
}
