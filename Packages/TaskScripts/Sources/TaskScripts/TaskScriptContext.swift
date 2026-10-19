/// What a script is told about its task, as `NATIVE_*` environment variables. Every variable is set
/// for every event, empty when Native doesn't know it (setup runs before the task has an id or a
/// title).
public struct TaskScriptContext: Hashable, Sendable {
    public var event: TaskScriptEvent
    /// The project's main checkout.
    public var projectPath: String
    /// The task's folder, where the script runs: its worktree, or the project's own folder for a task
    /// without one (and once a deleted task's worktree is gone).
    public var worktreePath: String
    public var branch: String?
    /// The branch the task's worktree was made from.
    public var baseBranch: String?
    /// The agent's id for the task's session.
    public var taskID: String?
    public var taskTitle: String?
    /// The agent's id: `claude-code`, `codex`, or a plugin's.
    public var agent: String?

    public init(
        event: TaskScriptEvent, projectPath: String, worktreePath: String, branch: String? = nil,
        baseBranch: String? = nil, taskID: String? = nil, taskTitle: String? = nil, agent: String? = nil
    ) {
        self.event = event
        self.projectPath = projectPath
        self.worktreePath = worktreePath
        self.branch = branch
        self.baseBranch = baseBranch
        self.taskID = taskID
        self.taskTitle = taskTitle
        self.agent = agent
    }

    /// The variables Native adds to the login shell's environment.
    public var environment: [String: String] {
        var environment = [
            "NATIVE_EVENT": event.rawValue,
            "NATIVE_PROJECT_PATH": projectPath,
            "NATIVE_WORKTREE_PATH": worktreePath,
            "NATIVE_BRANCH": branch ?? "",
            "NATIVE_BASE_BRANCH": baseBranch ?? "",
            "NATIVE_TASK_ID": taskID ?? "",
            "NATIVE_TASK_TITLE": taskTitle ?? "",
            "NATIVE_AGENT": agent ?? "",
        ]
        if event == .setup {
            // What setup scripts were told before there were other events, so theirs keep working.
            environment["NATIVE_WORKSPACE_PATH"] = worktreePath
            environment["NATIVE_ROOT_PATH"] = projectPath
        }
        return environment
    }

    /// The same task, for another event.
    public func with(_ event: TaskScriptEvent) -> TaskScriptContext {
        var context = self
        context.event = event
        return context
    }
}
