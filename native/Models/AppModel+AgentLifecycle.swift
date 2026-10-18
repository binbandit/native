import ACP
import Foundation
import os

/// Agents run only while something needs them, since each one holds a few hundred megabytes: at
/// launch the default agent and the ones the sidebar needs a fresh listing from, later whichever
/// one a session, sign-in or tool asks for. One that sits unused stops again, and its sessions keep
/// showing from the saved catalog.
extension AppModel {
    /// The agents' runtimes, in plugin order.
    var agents: [AgentRuntime] {
        runtimes.all
    }

    func runtime(_ agent: AgentDefinition.ID) -> AgentRuntime? {
        runtimes[agent]
    }

    /// How long an agent sits unused before it stops. The `agentIdleTimeout` default (seconds)
    /// shortens it, for trying the behavior out.
    static var agentIdleTimeout: Duration {
        let seconds = UserDefaults.standard.double(forKey: "agentIdleTimeout")
        return seconds > 0 ? .seconds(seconds) : .seconds(5 * 60)
    }

    /// Whether starting a session makes sense now, in `project` with `agent` (by default the
    /// current project and the default agent): one isn't already starting, and the agent can take
    /// it, even if it has to start first. Before the first check for agents, it assumes so; New
    /// Session waits for the check.
    func canCreateSession(in project: Project.ID? = nil, with agent: AgentDefinition.ID? = nil) -> Bool {
        guard (project ?? currentProject?.id) != nil, !isCreatingSession else { return false }
        guard let agent = agent ?? defaultAgent?.id, let runtime = runtimes[agent] else { return !hasCheckedAgents }
        return runtime.isAvailable
    }

    /// Waits for the first check for installed agents, which makes their runtimes.
    func agentsChecked() async {
        guard !hasCheckedAgents else { return }
        await withCheckedContinuation { agentCheckWaiters.append($0) }
    }

    /// Starts `agent` if it isn't running and waits until it's ready, first waiting for the check
    /// for agents if it hasn't made a runtime yet. Nil when it can't start (it isn't installed, or
    /// it failed), with `startFailure(of:)` saying why.
    @discardableResult
    func ensureRunning(_ agent: AgentDefinition.ID) async -> AgentRuntime? {
        if runtimes[agent] == nil {
            await agentsChecked()
        }
        guard let runtime = runtimes[agent] else { return nil }
        if runtime.status == .idle {
            let environment = await shellEnvironment()
            // Another caller may have started it while the environment loaded.
            if runtime.status == .idle {
                await start(runtime, environment: environment)
            }
        }
        await runtime.finishStarting()
        return runtime.isReady ? runtime : nil
    }

    /// Why `agent` couldn't start, for an alert.
    func startFailure(of agent: AgentDefinition.ID) -> String {
        guard let runtime = runtimes[agent] else {
            guard let definition = plugins.agent(agent) else { return "That agent isn't available anymore." }
            return "\(definition.displayName) isn't installed. Add Agent shows how to install it."
        }
        let reason = runtime.status.guidance ?? runtime.status.label
        return "Couldn't start \(runtime.agent.displayName): \(reason)"
    }

    /// The agents worth starting without being asked: the default one, so a new session starts
    /// right away, and the ones whose sessions the sidebar shows or that haven't listed a project
    /// yet, so the sidebar is current. Internal only for AppModel.swift.
    func agentsWorthStarting() -> Set<AgentDefinition.ID> {
        var agents = Set(sessionList.map(\.agent.id))
        if let agent = defaultAgent?.id {
            agents.insert(agent)
        }
        for runtime in self.agents
        where projects.all.contains(where: { !catalog.hasListed(runtime.agent.id, in: $0.id) }) {
            agents.insert(runtime.agent.id)
        }
        return agents
    }

    /// Stops agents that sit unused for `agentIdleTimeout`, for as long as the model lives. The
    /// default agent keeps running, so a new session never waits for one to start. Internal only
    /// for AppModel.swift.
    func parkAgentsWhenIdle() {
        let timeout = Self.agentIdleTimeout
        let interval = min(.seconds(60), timeout / 5)
        Task { [weak self] in
            var idleSince: [AgentDefinition.ID: ContinuousClock.Instant] = [:]
            while true {
                try? await Task.sleep(for: interval)
                guard let self else { return }
                let now = ContinuousClock.now
                for runtime in agents where runtime.isReady {
                    let agent = runtime.agent.id
                    if agent == defaultAgent?.id || isInUse(agent) {
                        idleSince[agent] = nil
                    } else if let since = idleSince[agent] {
                        if now - since >= timeout {
                            park(runtime)
                            idleSince[agent] = nil
                        }
                    } else {
                        idleSince[agent] = now
                    }
                }
            }
        }
    }

    private func park(_ runtime: AgentRuntime) {
        Self.logger.info("Stopping \(runtime.agent.displayName, privacy: .public), unused for a while")
        runtime.park()
        sessions.removeAll(of: runtime.agent.id)
    }

    /// Whether stopping `agent` would lose something: a session it's starting or signing in for,
    /// or an open session (or the one that started it) that's busy, showing or holding a draft.
    private func isInUse(_ agent: AgentDefinition.ID) -> Bool {
        if creatingSessionWith == agent || runtimes[agent]?.isSigningIn == true {
            return true
        }
        return sessions.open(of: agent).contains { isBusy($0) || isBusy($0.root) }
    }

    private func isBusy(_ session: SessionModel) -> Bool {
        session.key == selection || session.phase == .loading || session.phase == .prompting
            || !session.queue.isEmpty || session.isRetryScheduled || session.wait != nil || !session.draft.isEmpty
    }
}
