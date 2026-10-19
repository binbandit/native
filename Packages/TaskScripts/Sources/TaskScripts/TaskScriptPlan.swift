import Foundation

/// What runs for an event in a project, in order, and what waits on the user.
public struct TaskScriptPlan: Hashable, Sendable {
    public var event: TaskScriptEvent
    /// Run one after another; the first that fails stops the rest.
    public var scripts: [TaskScript]
    /// The repository's script, when the project hasn't allowed its repository's scripts yet. It
    /// takes the place of the project's script kept in Native, so that one doesn't run either.
    public var awaitingApproval: TaskScript?
    /// For all of `scripts` together.
    public var timeout: Duration

    public init(
        event: TaskScriptEvent, scripts: [TaskScript], awaitingApproval: TaskScript? = nil, timeout: Duration
    ) {
        self.event = event
        self.scripts = scripts
        self.awaitingApproval = awaitingApproval
        self.timeout = timeout
    }

    public var isEmpty: Bool {
        scripts.isEmpty && awaitingApproval == nil
    }
}

/// Which kinds of scripts may run, as the organization decides (`policy.taskScripts.*`).
public struct TaskScriptPermissions: Hashable, Sendable {
    /// Scripts written in Native: global, and each project's own.
    public var userScripts: Bool
    /// Scripts committed to repositories.
    public var repositoryScripts: Bool

    public init(userScripts: Bool = true, repositoryScripts: Bool = true) {
        self.userScripts = userScripts
        self.repositoryScripts = repositoryScripts
    }

    public static let all = TaskScriptPermissions()
}

extension TaskScriptConfiguration {
    /// What runs for `event` in the project whose main checkout is at `project` (nil for a folder
    /// outside any project), given the repository's own scripts by event (`repository`, read from
    /// its `.native/` folder) and what the organization allows.
    ///
    /// The project's script is the repository's when it has one, otherwise the one kept in Native.
    /// It runs after the global script, or instead of it when the user chose that for the project.
    public func plan(
        for event: TaskScriptEvent, project: URL?, repository: [TaskScriptEvent: String] = [:],
        permissions: TaskScriptPermissions = .all
    ) -> TaskScriptPlan {
        let settings = project.map(self.project(at:)) ?? ProjectTaskScripts()
        var own: TaskScript?
        var awaitingApproval: TaskScript?
        if permissions.repositoryScripts, let text = repository[event]?.runnable {
            let script = TaskScript(event: event, source: .repository, text: text)
            if settings.allowsRepositoryScripts {
                own = script
            } else {
                awaitingApproval = script
            }
        } else if permissions.userScripts, let text = settings.scripts[event]?.runnable {
            own = TaskScript(event: event, source: .project, text: text)
        }
        let global = permissions.userScripts ? global[event]?.runnable : nil
        let scripts: [TaskScript?] =
            switch settings.combination(for: event) {
            case .afterGlobal: [global.map { TaskScript(event: event, source: .global, text: $0) }, own]
            case .insteadOfGlobal: [own]
            }
        return TaskScriptPlan(
            event: event, scripts: scripts.compactMap(\.self), awaitingApproval: awaitingApproval,
            timeout: timeout(for: event))
    }
}

extension String {
    /// The script, unless it's only whitespace.
    fileprivate var runnable: String? {
        trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : self
    }
}
