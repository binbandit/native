import ACP
import Foundation
import Git
import NativeHostClient
import NativeHostProtocol
import os

// Agents and sessions in Native's host (docs/durability.md, Phase 2; `HostSessions`). The host
// runs the agents, so their work carries on when Native quits; the app follows the host's events
// and turns the user's actions into host requests.
extension AppModel {
    /// Runs every agent and session through the host `client` reaches from now on. Called once,
    /// before `start()`, when the host is on and connected; without it agents run in the app.
    func connectHost(client: NativeHostClient) {
        guard runtimes.host == nil else { return }
        runtimes.host = client
    }

    /// Whether agents run in Native's host rather than in the app.
    var runsAgentsInHost: Bool {
        runtimes.host != nil
    }

    /// Starts following the host's events, before anything asks the host for work. Internal only
    /// for AppModel.swift.
    func followHost() async {
        guard let host = runtimes.host else { return }
        await followCoordinators(on: host)
        sessions.onAgentSessionReplaced = { [weak self] session, summary in
            self?.followReplacedAgentSession(session, summary)
        }
        sessions.claimSubagent = { [weak self] parent, id, update in
            self?.claimHostTask(in: parent, id: id, update: update)
        }
        _ = await host.addEventHandler { [weak self] event in
            await self?.receiveFromHost(event)
        }
    }

    /// The host started a fresh agent session in place of one the agent never saved (it went away
    /// before the first turn), keeping the task: it carries on under the new id, with its title,
    /// settings, place in the sidebar and draft.
    private func followReplacedAgentSession(_ old: SessionModel, _ summary: HostSessionSummary) {
        // The host that holds it: this Mac's, or a paired one.
        guard let host = old.host?.client ?? runtimes.host, let agentSessionID = summary.agentSessionID else { return }
        let session = SessionModel(
            agent: old.agent, id: agentSessionID, summary: summary, client: host, services: old.services,
            promptCapabilities: old.promptCapabilities, origin: old.origin, parent: nil)
        session.mirror = old.mirror
        session.draft = old.draft
        session.attachments = old.attachments
        old.attachmentReads.move(to: session)
        session.heldPrompts = old.heldPrompts
        session.hasSubmittedPrompt = old.hasSubmittedPrompt
        session.isModelChangeSource = old.isModelChangeSource
        session.continuedTaskKey = old.taskPresentationKey
        session.modelChange = old.modelChange
        old.modelChange?.replace(old, with: session)
        sessions.services.modelContinuations.replace(old.key, with: session.key)
        session.quoteSelection = old.quoteSelection
        session.quoteSelectionSource = old.quoteSelectionSource
        session.isChangingWorkspace = old.isChangingWorkspace
        session.isWorkspaceReplaced = old.isWorkspaceReplaced
        session.mirrorState()
        sessions.replace(old, with: session)
        catalog.swap(old.key, for: SessionInfo(sessionId: agentSessionID, cwd: old.cwd.folderPath, updatedAt: .now))
        ordering.replace(old.key, with: session.key)
        taskPairs.replace(old.key, with: session.key)
        if let title = titles.namedTitle(for: old.titleKey) {
            titles.rename(session.titleKey, to: title)
        }
        let chosen = titles.configChoices(for: old.titleKey)
        titles.updateConfigChoices(for: session.titleKey) { $0.adopt(chosen) }
        history.replace(old.key, with: session.key)
        earlierConversations.replace(old.key, with: session.key)
        if selection == old.key {
            selection = session.key
        }
        followAgentChangeReplacement(old, with: session)
    }

    /// One of the host's events, in the order the host sent them. Nothing here may wait on the host
    /// (the client hands events over from its read loop), so requests go out on tasks.
    private func receiveFromHost(_ event: NativeHostClient.Event) {
        switch event {
        case .agentChanged(let agent):
            runtimes[AgentDefinition.ID(rawValue: agent.id)]?.apply(agent)
        case .connection(.connected):
            // Back after a dropped connection or a restarted host: what changed meanwhile.
            Task { await hostReconnected() }
        case .connection:
            break
        default:
            sessions.handle(event)
        }
    }

    private func hostReconnected() async {
        await syncHostAgents()
        await openWorkingHostSessions()
    }

    /// Tells the host the agents plugins provide now, with the environment plugins' launch policy
    /// adds, and takes in how each is doing. `refreshEnvironment` has the host read the user's
    /// login shell again (an agent was just installed, or signed in from a terminal). Internal
    /// only for AppModel.swift.
    func syncHostAgents(refreshEnvironment: Bool = false) async {
        guard let host = runtimes.host else { return }
        let specs = hostAgentSpecs
        do {
            // Where this app makes task worktrees, which the host lets paired clients reach.
            let worktrees =
                UserDefaults.standard.string(forKey: "gitWorktreesFolder")
                ?? Worktree.defaultLocation(home: nil).folderPath
            try await host.syncAgents(specs, refreshEnvironment: refreshEnvironment, worktreesFolder: worktrees)
            for agent in try await host.agents() {
                runtimes[AgentDefinition.ID(rawValue: agent.id)]?.apply(agent)
            }
        } catch {
            Self.logger.error("Couldn't sync agents with the host: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// The agents plugins provide now, as a host launches them, with the environment plugins'
    /// launch policy adds. Paired hosts get them too (AppModel+Hosts.swift).
    var hostAgentSpecs: [AgentSpec] {
        plugins.agents.map { agent in
            var spec = AgentSpec(agent)
            spec.env.merge(plugins.launchEnvironment(for: agent.id)) { $1 }
            return spec
        }
    }

    /// Opens the user's sessions the host is working on, has messages queued for, or that wait for
    /// the user, so the sidebar shows them as they are, including what happened while Native was
    /// closed. The rest open when the user selects them.
    func openWorkingHostSessions() async {
        guard let host = runtimes.host, let summaries = try? await host.sessions() else { return }
        for summary in summaries { sessions.recordActivity(summary) }
        for summary in summaries
        where summary.origin == .user && summary.parentID == nil
            && (summary.isWorking || summary.needsApproval || !summary.queue.isEmpty)
        {
            guard let agentSessionID = summary.agentSessionID else { continue }
            let key = SessionKey(agent: AgentDefinition.ID(rawValue: summary.agentID), id: agentSessionID)
            guard sessions.session(key) == nil, catalog.contains(key) else { continue }
            await loadSession(key)
        }
    }

    /// Restarts an agent in the host with its plugin's current definition. Turns it was running
    /// pick up again on the new process, as after a crash. Internal only for AppModel.swift.
    func restartOnHost(_ agent: AgentDefinition.ID) async {
        guard let host = runtimes.host, let runtime = runtimes[agent] else { return }
        sessions.removeAll(of: agent)
        await syncHostAgents()
        do {
            runtime.apply(try await host.restartAgent(agent.rawValue))
        } catch {
            runtime.apply(
                HostAgent(
                    id: agent.rawValue, name: runtime.agent.displayName, state: .failed,
                    problem: error.localizedDescription))
            Self.logger.error(
                "Couldn't restart \(agent.rawValue, privacy: .public): \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Closes a session the user left unused, in the host and, where the agent can, in the agent's
    /// process, which frees what it holds. Its history stays with the agent.
    func closeOnHost(_ session: SessionModel, on runtime: AgentRuntime) {
        guard let host = session.host else { return }
        sessions.remove(session)
        let closeInAgent = runtime.capabilities?.closeSessions == true
        Task { try? await host.client.closeSession(host.id, closeInAgent: closeInAgent) }
    }
}
