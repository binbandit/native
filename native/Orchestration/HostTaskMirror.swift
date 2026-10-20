import ACP
import Foundation
import NativeHostClient
import NativeHostProtocol
import NativeOrchestration
import os

/// The tasks Native's host runs (`_native/tasks/*`), as the app shows them: by title where only a
/// task's id is known (a reloaded transcript names its sender by id), and out of the sidebar, since
/// they belong to the session that started them.
final class HostTaskMirror {
    static let shared = HostTaskMirror()

    private(set) var tasks: [String: HostTask] = [:]
    private var followed: Set<ObjectIdentifier> = []

    func task(id: String) -> HostTask? {
        tasks[id]
    }

    private var answering: Set<ObjectIdentifier> = []

    /// True the first time it's asked about `client`: who registers the handler for the app's tools
    /// on it, once.
    func answers(_ client: NativeHostClient) -> Bool {
        answering.insert(ObjectIdentifier(client)).inserted
    }

    /// Reads every task the host has, then takes in each change it announces.
    func follow(_ client: NativeHostClient, model: AppModel) async {
        if followed.insert(ObjectIdentifier(client)).inserted {
            await client.addTaskHandler { [weak self, weak model] task in
                await MainActor.run {
                    guard let model else { return }
                    self?.take(task, into: model)
                }
            }
        }
        do {
            for task in try await client.tasks() {
                take(task, into: model)
            }
        } catch {
            OrchestrationPlugin.logger.error(
                "Couldn't read the host's tasks: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func take(_ task: HostTask, into model: AppModel) {
        tasks[task.id] = task
        let key = SessionKey(agent: AgentDefinition.ID(rawValue: task.agentID), id: task.agentSessionID)
        guard !model.taskRecords.contains(key) else { return }
        model.taskRecords.add(
            TaskSessionRecords.Record(
                key: key, cwd: URL(filePath: task.cwd ?? "/", directoryHint: .isDirectory),
                parent: SessionKey(
                    agent: AgentDefinition.ID(rawValue: task.parentAgentID), id: task.parentAgentSessionID)))
    }
}
