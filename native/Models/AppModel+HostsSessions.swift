import ACP
import Foundation
import Git
import NativeHostClient
import NativeHostProtocol
import NativeLink
import os

// Sessions on paired hosts in the sidebar and the detail column: each project lists the sessions
// its checkouts on paired hosts have, beside this Mac's, and selecting one opens it on its host.
extension AppModel {
    /// `project`'s sessions on paired hosts: the ones each host has open in its checkout, then the
    /// ones its agents saved there, newest first. Offline hosts list nothing new; what's open here
    /// stays open.
    func remoteSessionSummaries(in project: Project.ID) -> [SessionSummary] {
        guard offersRemoteHosts, let project = projects.project(project) else { return [] }
        var summaries: [SessionSummary] = []
        var seen: Set<SessionKey> = []
        for checkout in project.checkouts {
            guard let host = hosts.host(checkout.host) else { continue }
            func belongsToCheckout(_ folder: String) -> Bool {
                host.isTaskFolder(folder, ofCheckoutAt: checkout.path)
                    || checkout.taskFolders?.contains(where: { RemoteHost.plain($0) == RemoteHost.plain(folder) })
                        == true
            }
            // Sessions the host knows were delegated by another, or belong to one: never a task of
            // their own, though their agent lists them in the same folder.
            let notTasks = Set(
                host.sessions.filter { $0.origin != .user || $0.parentID != nil }.compactMap { summary in
                    summary.agentSessionID.map {
                        SessionKey(agent: AgentDefinition.ID(rawValue: summary.agentID), id: $0)
                    }
                })
            for summary in host.sessions
            where summary.origin == .user && summary.parentID == nil
                && belongsToCheckout(summary.cwd)
            {
                guard let agentSessionID = summary.agentSessionID,
                    let runtime = host.runtime(AgentDefinition.ID(rawValue: summary.agentID))
                else { continue }
                let info = SessionInfo(
                    sessionId: agentSessionID, cwd: summary.cwd, title: summary.title, updatedAt: summary.lastActivity)
                let entry = SessionSummary(project: project.id, agent: runtime.agent, info: info)
                hosts.deviceWorkspaces?.remember(entry.id, on: host.id)
                if !deletedSessions.contains(entry.id), seen.insert(entry.id).inserted { summaries.append(entry) }
            }
            for (folder, listings) in host.history where belongsToCheckout(folder) {
                for listed in listings where !notTasks.contains(listed.key) {
                    guard let runtime = host.runtime(listed.agent) else { continue }
                    let entry = SessionSummary(project: project.id, agent: runtime.agent, info: listed.info)
                    hosts.deviceWorkspaces?.remember(entry.id, on: host.id)
                    if !deletedSessions.contains(entry.id), seen.insert(entry.id).inserted { summaries.append(entry) }
                }
            }
        }
        return summaries
    }

    /// Opens a remote session the sidebar listed, on its host, replaying it from the agent there.
    /// Returns false for a session that isn't remote, which opens the usual way.
    func loadRemoteSession(_ key: SessionKey) async -> Bool {
        guard offersRemoteHosts, sessions.session(key) == nil, let place = remotePlace(of: key) else { return false }
        openFailures[key] = nil
        guard let runtime = place.host.runtime(key.agent) else {
            openFailures[key] = SessionOpenFailure(.agentMissing, agent: key.agent.rawValue)
            return true
        }
        if !runtime.isReady { await runtime.startOnHost() }
        guard sessions.session(key) == nil else { return true }
        do {
            _ = try await launcher.load(
                key, cwd: URL(filePath: place.cwd, directoryHint: .isDirectory), title: place.title, on: runtime)
        } catch {
            guard sessions.session(key) == nil else { return true }
            openFailures[key] = SessionOpenFailure(error, agent: runtime.agent.displayName)
        }
        return true
    }

    /// The runtime of the agent a session runs on: its host's for a session on a paired host, else
    /// this Mac's. Deleting a task's copy and pinning go through it, so they reach the right agent.
    func agentRuntime(for key: SessionKey) -> AgentRuntime? {
        taskRuntime(for: taskActionOwner(for: key), agent: key.agent)
    }

    /// `agentRuntime(for:)`, started if it's idle.
    func ensureRunning(for key: SessionKey) async -> AgentRuntime? {
        let owner = taskActionOwner(for: key)
        if owner == .local { return await ensureRunning(key.agent) }
        guard let runtime = taskRuntime(for: owner, agent: key.agent), runtime.isAvailable else { return nil }
        if !runtime.isReady { await runtime.startOnHost() }
        return runtime.isReady ? runtime : nil
    }

    /// Tells the catalog which project each session on a paired host belongs to, so archiving,
    /// pinning and the rest find it as they find this Mac's. Run when a host's sessions change.
    func indexRemoteSessions() {
        guard offersRemoteHosts else { return }
        var index: [SessionKey: (project: Project.ID, info: SessionInfo)] = [:]
        for project in projects.all + projects.archived {
            for summary in remoteSessionSummaries(in: project.id) where index[summary.id] == nil {
                index[summary.id] = (project.id, summary.info)
            }
        }
        catalog.remote = index
    }

    /// The host a listed remote session lives on, and its folder and title there.
    func remotePlace(of key: SessionKey) -> (host: RemoteHost, cwd: String, title: String?)? {
        for host in hosts.all {
            if let summary = host.sessions.first(where: {
                $0.agentID == key.agent.rawValue && $0.agentSessionID == key.id
            }) {
                return (host, summary.cwd, summary.title)
            }
            for listed in host.history.values.joined() where listed.key == key {
                return (host, listed.info.cwd, listed.info.title)
            }
        }
        return nil
    }

    /// A host (re)connected and listed its agents and sessions: move the tasks still open on an
    /// earlier pairing's client to it, open the user's sessions it's working on, has messages queued
    /// for or that wait for the user, so the sidebar shows them as they are, then list what its
    /// agents saved in its checkouts.
    func hostConnected(_ host: RemoteHost) async {
        if let client = host.client, hosts.wiredClients.insert(ObjectIdentifier(client)).inserted {
            // Titles for its tasks, as for this Mac's host, before any session opens on it.
            await HostTitlesWiring.connect(self, to: client)
        }
        await reattachSessions(to: host)
        await syncAgents(to: host)
        for summary in host.sessions
        where summary.origin == .user && summary.parentID == nil
            && (summary.isWorking || summary.needsApproval || !summary.queue.isEmpty)
        {
            guard let agentSessionID = summary.agentSessionID else { continue }
            let key = SessionKey(agent: AgentDefinition.ID(rawValue: summary.agentID), id: agentSessionID)
            _ = await loadRemoteSession(key)
        }
        await findCheckouts(on: host)
        await refreshRemoteHistory(on: host)
        indexRemoteSessions()
        resumeComposeHold(on: host)
    }

    /// Gives a paired host this Mac's agents, as its own host gets them: a host with no Native.app
    /// of its own (a Mac mini nobody sits at) knows no agents until a client says. Only with the
    /// `runCommands` grant, since agent specs are commands; never this Mac's worktrees folder, and
    /// never a spec whose command is a path on this Mac.
    func syncAgents(to host: RemoteHost) async {
        guard let client = host.client, host.paired.grants.runCommands else { return }
        let specs = hostAgentSpecs.filter { !$0.command.hasPrefix("/") }
        do {
            try await client.syncAgents(specs)
            await host.refresh()
        } catch {
            Self.logger.error(
                "Couldn't give \(host.name, privacy: .public) the agents: \(error.localizedDescription, privacy: .public)"
            )
        }
    }

    /// Lists the sessions agents saved in each of `host`'s checkouts and their task worktrees there,
    /// after it connects.
    func refreshRemoteHistory(on host: RemoteHost) async {
        var folders: [String] = []
        let git = host.client.map(Git.onHost)
        for project in projects.all {
            guard let checkout = project.checkoutPath(on: .remote(host.id)) else { continue }
            folders.append(checkout)
            folders += project.checkouts.first(where: { $0.host == host.id })?.taskFolders ?? []
            // Its task worktrees are named after the repository, not this checkout's folder.
            if let name = try? await git?.repository(at: URL(filePath: checkout, directoryHint: .isDirectory))?.name {
                host.noteRepositoryName(name, ofCheckoutAt: checkout)
            }
            // Its tasks run in their own worktrees there, as here; their sessions are listed by folder.
            if let workspaces = await taskWorkspaces(on: host) {
                folders += await workspaces.taskFolders(of: project.onHost(at: checkout)).map(\.folderPath)
            }
        }
        await host.refreshHistory(in: folders)
    }
}
