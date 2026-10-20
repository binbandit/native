import ACP
import Foundation
import NativeHostProtocol
import NativeOrchestration

// Tasks Native's host runs (`HostTasks`): the host shows each one in its parent's transcript as a
// card naming the task's session, and the app follows that session as the task it is, so the user
// can open it, read it and talk to it, as with a task the app started.
extension AppModel {
    /// The model for a task the host showed in `parent`'s transcript, or nil when `update` isn't
    /// one of Native's task cards (an agent's own subagent).
    func claimHostTask(in parent: SessionModel, id: SessionID, update: JSONValue) -> SessionModel? {
        guard let card = TaskTranscript.CardMeta(update: update), let client = runtimes.host,
            let runtime = runtimes[AgentDefinition.ID(rawValue: card.agent)]
        else { return nil }
        let hostID = HostSessionID(card.clientID)
        // Attaching brings the host's summary; until then the task reads as loading.
        let summary =
            sessions.hostSummaries[hostID]
            ?? HostSessionSummary(
                id: hostID, agentID: card.agent, agentName: runtime.agent.displayName, agentSessionID: id,
                cwd: parent.cwd.folderPath, parentID: parent.host?.id, origin: .task, phase: .loading)
        let key = SessionKey(agent: runtime.agent.id, id: id)
        if !taskRecords.contains(key) {
            taskRecords.add(TaskSessionRecords.Record(key: key, cwd: parent.cwd, parent: parent.key))
        }
        return SessionModel(
            agent: runtime.agent, id: id, summary: summary, client: client, services: parent.services,
            promptCapabilities: runtime.capabilities?.prompt ?? PromptCapabilities(), origin: .task, parent: parent)
    }
}
