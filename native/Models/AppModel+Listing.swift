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
        var positions: [SessionID: Int] = [:]
        // Some agents list a repository's sessions from each of its worktrees; keep one copy, the
        // one fetched for the session's own folder.
        func merge(_ page: [SessionInfo], from folder: String) {
            for info in page {
                if let position = positions[info.sessionId] {
                    if info.cwd == folder {
                        fetched[position] = info
                    }
                } else {
                    positions[info.sessionId] = fetched.count
                    fetched.append(info)
                }
            }
        }
        do {
            // The project's own folder, and the folders Native made for its tasks (worktrees).
            let folders = [project.path] + (await taskWorkspaces?.taskFolders(of: project) ?? []).map(\.folderPath)
            for folder in Set(folders).sorted() {
                merge(try await SessionCatalog.fetch(cwd: folder, from: connection), from: folder)
            }
        } catch {
            if !runtime.noteSignInRequired(by: error) {
                errorMessage = "Couldn't list \(runtime.agent.displayName) sessions in \(project.name): \(error.localizedDescription)"
            }
            return
        }
        // Agents that match folders exactly don't list a session whose folder the provider no longer
        // reports (an archived task's removed worktree, or one it couldn't look up just now), so
        // ask those folders too before dropping what was listed before. Best effort: a folder that's
        // gone may fail.
        let missingFolders = Set(
            catalog.sessions(in: project.id, of: agent).filter { positions[$0.sessionId] == nil }.map(\.cwd))
        for folder in missingFolders.sorted() {
            if let page = try? await SessionCatalog.fetch(cwd: folder, from: connection) {
                merge(page, from: folder)
            }
        }
        Self.logger.debug("\(runtime.agent.displayName, privacy: .public) lists \(fetched.count) sessions in \(project.path, privacy: .public)")
        guard projects.project(project.id) != nil, runtimes[agent] === runtime else { return }
        // Only the user's own sessions are listed: subagents belong under their parent, and task
        // sessions to whatever started them, in this run or an earlier one. While a task session is
        // starting, its id isn't known yet, so sessions new to the listing wait for the next one.
        let isStartingTask = taskStartsInFlight[agent, default: 0] > 0
        let known = Set(catalog.sessions(in: project.id, of: agent).map(\.sessionId))
        let topLevel = fetched.filter { info in
            let key = SessionKey(agent: agent, id: info.sessionId)
            return !taskRecords.contains(key) && !deletedSessions.contains(key)
                && (sessions.session(key)?.origin ?? .user) == .user
                && (!isStartingTask || known.contains(info.sessionId))
        }
        catalog.replace(agent, in: project.id, with: topLevel) { sessions.session(SessionKey(agent: agent, id: $0)) != nil }
        if let selection, selection.agent == agent, !catalog.contains(selection) {
            self.selection = nil
        }
    }
}
