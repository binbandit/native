import ACP
import Foundation
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
        _ = await host.addEventHandler { [weak self] event in
            await self?.receiveFromHost(event)
        }
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
        let specs = plugins.agents.map { agent in
            var spec = AgentSpec(agent)
            spec.env.merge(plugins.launchEnvironment(for: agent.id)) { $1 }
            return spec
        }
        do {
            try await host.syncAgents(specs, refreshEnvironment: refreshEnvironment)
            for agent in try await host.agents() {
                runtimes[AgentDefinition.ID(rawValue: agent.id)]?.apply(agent)
            }
        } catch {
            Self.logger.error("Couldn't sync agents with the host: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Opens the user's sessions the host is working on, has messages queued for, or that wait for
    /// the user, so the sidebar shows them as they are, including what happened while Native was
    /// closed. The rest open when the user selects them.
    func openWorkingHostSessions() async {
        guard let host = runtimes.host, let summaries = try? await host.sessions() else { return }
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
            Self.logger.error(
                "Couldn't restart \(agent.rawValue, privacy: .public): \(error.localizedDescription, privacy: .public)")
        }
        if let selection, selection.agent == agent {
            await loadSession(selection)
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
