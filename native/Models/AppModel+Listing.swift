import ACP
import Foundation
import TaskList
import os

// The sidebar's sessions: each project's, in order, and listing them from each agent with `session/list`.
extension AppModel {
    /// A project's sessions from every agent, in the user's order, then most recently active first.
    /// Kept between calls until something it's built from changes, since views ask on every update.
    func sessions(in project: Project.ID) -> [SessionSummary] {
        sessionLists.list(for: project) {
            // A conversation `/clear` set aside opens from the one that replaced it, not the sidebar.
            let summaries = allSessions(in: project).filter { summary in
                !archivedSessions.contains(summary.id) && !pendingDeletionKeys.contains(summary.id)
                    && !ordering.isPinned(summary.id) && !earlierConversations.isSetAside(summary.id)
            }
            return ordering.sorted(summaries, in: project, recency: lastActive)
        }
    }

    /// A project's sessions from every agent, archived ones included.
    func allSessions(in project: Project.ID) -> [SessionSummary] {
        agents.flatMap { runtime in
            catalog.sessions(in: project, of: runtime.agent.id).map {
                SessionSummary(project: project, agent: runtime.agent, info: $0)
            }
        } + remoteSessionSummaries(in: project)
    }

    /// Every session in the sidebar, in its order: pinned first, then each project's.
    var sessionList: [SessionSummary] {
        pinnedSessions + projects.all.flatMap { sessions(in: $0.id) }
    }

    func moveSessions(in project: Project.ID, fromOffsets source: IndexSet, toOffset destination: Int) {
        ordering.move(sessions(in: project).map(\.id), in: project, fromOffsets: source, toOffset: destination)
    }

    private func lastActive(_ summary: SessionSummary) -> Date {
        lastActivity(for: summary) ?? .distantPast
    }

    /// One activity date for task ages and ordering, whether or not its transcript is open.
    func lastActivity(for summary: SessionSummary) -> Date? {
        sessions.activityDates.date(
            for: summary.id, listed: summary.info.updatedDate, live: sessions.session(summary.id)?.lastActivity)
    }

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
        checkFolder(of: project)
        guard let connection = runtime.connection, runtime.capabilities?.listSessions == true else { return }
        let agent = runtime.agent.id
        listingsInFlight[agent, default: 0] += 1
        projectListingsInFlight[project.id, default: 0] += 1
        defer {
            listingsInFlight[agent, default: 1] -= 1
            projectListingsInFlight[project.id, default: 1] -= 1
        }
        var fetched: [SessionInfo] = []
        var positions: [SessionID: Int] = [:]
        // The project's own folder, and the folders Native made for its tasks (worktrees).
        var folders = [project.path]
        // A folder as Native knows it (`/tmp/x`), not the resolved spelling an agent may have
        // recorded (Codex's `/private/tmp/x`), so it shows and compares as the project does.
        func knownSpelling(_ path: String) -> String {
            guard !folders.contains(path) else { return path }
            return folders.first { SessionFolder.isSame($0, path) } ?? path
        }
        // Some agents list a repository's sessions from each of its worktrees; keep one copy, the
        // one fetched for the session's own folder.
        func merge(_ page: [SessionInfo], from folder: String) {
            for var info in page {
                info.cwd = knownSpelling(info.cwd)
                if let position = positions[info.sessionId] {
                    if info.cwd == knownSpelling(folder) {
                        fetched[position] = info
                    }
                } else {
                    positions[info.sessionId] = fetched.count
                    fetched.append(info)
                }
            }
        }
        do {
            folders += (await taskWorkspaces?.taskFolders(of: project) ?? []).map(\.folderPath)
            // Each under every spelling an agent may have recorded it by.
            for folder in Set(folders.flatMap(SessionFolder.listingPaths)).sorted() {
                merge(try await SessionCatalog.fetch(cwd: folder, from: connection), from: folder)
            }
        } catch ACPConnectionError.disconnected {
            // The agent stopped mid-listing: parked while idle, restarted, or crashed (which recovery
            // reports). That isn't the listing's failure; the agent lists again when it next starts.
            return
        } catch {
            // A replaced agent's listing no longer matters, one that wants the user to sign in says
            // so itself, and a missing folder already explains why listing it failed.
            guard runtimes[agent] === runtime, !runtime.noteSignInRequired(by: error),
                !problems.list(for: project.id).contains(where: { $0.work == .folder })
            else { return }
            problems.report(listingProblem(in: project, of: runtime.agent, details: error.localizedDescription))
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
        Self.logger.debug(
            "\(runtime.agent.displayName, privacy: .public) lists \(fetched.count) sessions in \(project.path, privacy: .public)"
        )
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
        catalog.replace(agent, in: project.id, with: topLevel) {
            sessions.session(SessionKey(agent: agent, id: $0)) != nil
        }
        problems.resolve(.listing(agent), in: project.id)
        if let selection, selection.agent == agent, !catalog.contains(selection), startingTask(selection) == nil {
            self.selection = nil
        }
    }

    /// Whether a project's sessions are still being found: no agent has listed it yet, and one is
    /// listing it, or starting and able to. Until then an empty project isn't known to be empty.
    func isFindingSessions(in project: Project.ID) -> Bool {
        guard !catalog.hasListedAny(in: project) else { return false }
        if projectListingsInFlight[project, default: 0] > 0 || !hasCheckedAgents { return true }
        return agents.contains { runtime in
            runtime.status == .starting || (runtime.isReady && runtime.capabilities?.listSessions == true)
        }
    }

    /// Lists `project` from `agent` again after a failure, starting the agent first if it's stopped.
    func retryListing(in project: Project, of agent: AgentDefinition.ID) async {
        guard let runtime = await ensureRunning(agent) else {
            if let definition = runtimes[agent]?.agent {
                problems.report(listingProblem(in: project, of: definition, details: startFailure(of: agent)))
            } else {
                // The agent went away (uninstalled), and its sessions with it.
                problems.resolve(.listing(agent), in: project.id)
            }
            return
        }
        guard runtime.capabilities?.listSessions == true else {
            // Nothing to list from an agent that no longer lists sessions.
            problems.resolve(.listing(agent), in: project.id)
            return
        }
        await refreshSessions(in: project, of: runtime)
    }

    /// The problem saying a project's folder is gone, while it is; no task can start there.
    func missingFolder(of project: Project.ID) -> ProjectProblem? {
        problems.list(for: project).first { $0.work == .folder }
    }

    /// Says when a project's folder on this Mac is gone, since agents list a missing folder as empty
    /// and starting a task there fails. Agents still list it, for sessions they kept from before.
    /// Internal only for AppModel+Problems.swift.
    func checkFolder(of project: Project) {
        guard project.host == .local else { return }
        guard !FileManager.default.fileExists(atPath: project.path) else {
            problems.resolve(.folder, in: project.id)
            return
        }
        problems.report(
            ProjectProblem(
                project: project.id,
                work: .folder,
                title: "Can't find this project's folder",
                recovery: "Native looked for it at \(project.path).",
                suggestion: "Move it back and retry, or delete the project from Native."
            ))
    }

    private func listingProblem(in project: Project, of agent: AgentDefinition, details: String) -> ProjectProblem {
        let hasListed = !catalog.sessions(in: project.id, of: agent.id).isEmpty
        return ProjectProblem(
            project: project.id,
            work: .listing(agent.id),
            title: "Couldn't list \(agent.displayName) tasks",
            recovery: hasListed
                ? "The sidebar shows the tasks \(agent.displayName) listed before."
                : "\(agent.displayName)'s tasks in \(project.name) show once it can list them.",
            details: details.withoutTerminalEscapes
        )
    }
}
