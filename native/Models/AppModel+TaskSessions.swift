import ACP
import Foundation

/// Sessions Native's own tools start and reopen (orchestration, automations, expeditions), which
/// stay out of the sidebar.
extension AppModel {
    /// Starts a session for Native's tools, out of the sidebar: one another session delegates work
    /// to (`parent`, Native's id for it; the session is its subagent and works in its folder unless
    /// `cwd` says otherwise), or a detached one such as a workflow step. Returned idle.
    func startTaskSession(agent: AgentDefinition.ID, cwd: URL? = nil, parent: UUID? = nil) async throws -> SessionModel
    {
        let parentSession = try parent.map { id in
            guard let session = sessions.session(clientID: id) else { throw SessionLauncher.LaunchError.parentClosed }
            return session
        }
        guard let runtime = await ensureRunning(agent) else {
            throw SessionLauncher.LaunchError.agentUnavailable(runtimes[agent]?.agent.displayName ?? agent.rawValue)
        }
        guard let cwd = cwd ?? parentSession?.cwd ?? currentProject?.url else {
            throw SessionLauncher.LaunchError.failed(
                agent: runtime.agent.displayName, underlying: CocoaError(.fileNoSuchFile))
        }
        // Until its record is written, the sidebar's listing mustn't take the new session for the user's.
        taskStartsInFlight[agent, default: 0] += 1
        defer { taskStartsInFlight[agent, default: 1] -= 1 }
        do {
            let project = await project(of: parentSession, folder: cwd)
            let session = try await launcher.start(
                on: runtime, cwd: cwd, project: project, origin: .task, parent: parentSession)
            taskRecords.add(TaskSessionRecords.Record(key: session.key, cwd: cwd, parent: parentSession?.key))
            return session
        } catch {
            runtime.noteSignInRequired(by: error)
            throw SessionLauncher.LaunchError.failed(agent: runtime.agent.displayName, underlying: error)
        }
    }

    /// Reopens a task session Native started, in this run or an earlier one, replaying its history
    /// and keeping it out of the sidebar. A delegated one rejoins its parent when that's open.
    /// Returns the open session if it already is.
    func reopenTaskSession(agent: AgentDefinition.ID, id: SessionID, cwd: URL) async throws -> SessionModel {
        let key = SessionKey(agent: agent, id: id)
        if let session = sessions.session(key) {
            return session
        }
        guard let runtime = await ensureRunning(agent) else {
            throw SessionLauncher.LaunchError.agentUnavailable(runtimes[agent]?.agent.displayName ?? agent.rawValue)
        }
        // Another caller may have opened it while the agent started.
        if let session = sessions.session(key) {
            return session
        }
        let record = taskRecords.record(key)
        let parent = record?.parent.flatMap(sessions.session)
        let session = try await launcher.load(key, cwd: cwd, on: runtime, origin: .task, parent: parent)
        taskRecords.add(TaskSessionRecords.Record(key: key, cwd: cwd, parent: record?.parent))
        return session
    }
}
