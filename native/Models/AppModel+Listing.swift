import ACP
import Foundation
import os

// Listing each agent's sessions in each project with `session/list`.
extension AppModel {
    func refreshSessions() async {
        await withTaskGroup(of: Void.self) { group in
            for project in projects.all {
                group.addTask { await self.refreshSessions(in: project) }
            }
        }
    }

    func refreshSessions(in project: Project) async {
        await withTaskGroup(of: Void.self) { group in
            for runtime in agents {
                group.addTask { await self.refreshSessions(in: project, of: runtime) }
            }
        }
    }

    func refreshSessions(of runtime: AgentRuntime) async {
        await withTaskGroup(of: Void.self) { group in
            for project in projects.all {
                group.addTask { await self.refreshSessions(in: project, of: runtime) }
            }
        }
    }

    private func refreshSessions(in project: Project, of runtime: AgentRuntime) async {
        guard let connection = runtime.connection, runtime.capabilities?.listSessions == true else { return }
        let agent = runtime.agent.id
        var fetched: [SessionInfo] = []
        do {
            // The project's own folder, and the folders Native made for its tasks (worktrees).
            let folders = [project.path] + (await taskWorkspaces?.taskFolders(of: project) ?? []).map(\.folderPath)
            for folder in Set(folders).sorted() {
                fetched += try await SessionCatalog.fetch(cwd: folder, from: connection)
            }
        } catch {
            if !runtime.noteSignInRequired(by: error) {
                errorMessage = "Couldn't list \(runtime.agent.displayName) sessions in \(project.name): \(error.localizedDescription)"
            }
            return
        }
        Self.logger.debug("\(runtime.agent.displayName, privacy: .public) lists \(fetched.count) sessions in \(project.path, privacy: .public)")
        guard projects.project(project.id) != nil, runtimes[agent] === runtime else { return }
        // Only the user's own sessions are listed: subagents belong under their parent, and task
        // sessions to whatever started them, in this run or an earlier one.
        let topLevel = fetched.filter { info in
            let key = SessionKey(agent: agent, id: info.sessionId)
            return !taskRecords.contains(key) && !deletedSessions.contains(key)
                && (sessions.session(key)?.origin ?? .user) == .user
        }
        catalog.replace(agent, in: project.id, with: topLevel) { sessions.session(SessionKey(agent: agent, id: $0)) != nil }
        if let selection, selection.agent == agent, !catalog.contains(selection) {
            self.selection = nil
        }
    }
}
