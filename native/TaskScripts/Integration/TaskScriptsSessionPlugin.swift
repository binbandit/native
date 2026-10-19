import ACP
import Foundation

/// Hands task starts and finished turns to the task scripts. A system plugin: scripts run only when
/// the user or the repository set some up, so there's nothing to switch off in Extensions.
struct TaskScriptsSessionPlugin: NativePlugin {
    /// Set by the app's wiring.
    static weak var center: TaskScriptCenter?

    let manifest = PluginManifest(id: "native.task-scripts", name: "Task Scripts")

    func handle(_ event: SessionEvent) async {
        guard let center = Self.center else { return }
        switch event {
        // Subagents work for their task; its own events are enough.
        case .sessionStarted(let session) where session.parentID == nil:
            center.taskStarted(in: session.cwd, task: TaskScriptTask(session))
        case .turnEnded(let session, _) where session.parentID == nil:
            center.turnFinished(in: session.cwd, task: TaskScriptTask(session))
        default:
            break
        }
    }
}

extension TaskScriptTask {
    init(_ session: SessionContext) {
        self.init(id: session.sessionID?.rawValue, title: session.title, agent: session.agent.rawValue)
    }
}
