/// When Native runs a task script. A small, fixed set: each has a file a repository can commit, a
/// default timeout, and an id scripts see as `NATIVE_EVENT`.
public enum TaskScriptEvent: String, CaseIterable, Hashable, Sendable, Identifiable {
    /// Runs in the project checkout before the base is fetched and the worktree is created.
    case beforeWorktree = "before-worktree"
    /// Runs in the new worktree without holding the first message.
    case afterWorktree = "after-worktree"
    /// Existing setup scripts hold messages until they finish or the user skips them.
    case setup
    /// A task started, in its worktree or in the project's folder.
    case taskStarted = "task-started"
    /// The agent finished a turn.
    case turnFinished = "turn-finished"
    /// A task's worktree is about to be removed, because the task was archived or deleted: stop
    /// servers, clean caches. It never stops the removal.
    case teardown
    /// A task was deleted for good, after the undo window.
    case taskDeleted = "task-deleted"

    public var id: Self { self }

    /// Where a repository commits the script, from its root.
    public var repositoryPath: String { ".native/\(rawValue).sh" }

    /// How long the script may run unless the user chose otherwise.
    public var defaultTimeout: Duration {
        (self == .setup || self == .beforeWorktree || self == .afterWorktree) ? .seconds(10 * 60) : .seconds(60)
    }

    /// Whether the task waits for it: setup holds the agent's turns until it's done or skipped.
    public var holdsTask: Bool { self == .setup }
}
