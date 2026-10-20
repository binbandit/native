import ACP
import Foundation
import NativeHostProtocol
import NativeOrchestration

/// Tasks by id, for views that only know the id: a reloaded session replays its task prompts with
/// the sender's id in their header.
enum Orchestrator {
    static func savedTask(id: String, defaults: UserDefaults = .standard) -> OrchestrationTask? {
        if let task = HostTaskMirror.shared.task(id: id) {
            return OrchestrationTask(
                id: task.id, session: TaskSessionRef(agent: task.agentID, id: task.agentSessionID.rawValue),
                agentName: task.agentName, title: task.title,
                parent: TaskSessionRef(agent: task.parentAgentID, id: task.parentAgentSessionID.rawValue),
                parentAgentName: task.parentAgentName, cwd: task.cwd, createdAt: task.createdAt)
        }
        return AppTaskRuntime.savedTasks(in: defaults).first { $0.id == id }
    }
}
