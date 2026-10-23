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
    /// current project and the default agent): the project's folder is there and the agent can take
    /// it, even if it has to start first. Before the first check
    /// for agents, it assumes so; New Session waits for the check.
    func canCreateSession(in project: Project.ID? = nil, with agent: AgentDefinition.ID? = nil) -> Bool {
        guard let project = project ?? currentProject?.id, missingFolder(of: project) == nil else { return false }
        guard let agent = agent ?? defaultAgent?.id, let runtime = runtimes[agent] else { return !hasCheckedAgents }
        return runtime.isAvailable
    }

    /// Waits for the first check for installed agents, which makes their runtimes.
    func agentsChecked() async {
        guard !hasCheckedAgents else { return }
        await withCheckedContinuation { agentCheckWaiters.append($0) }
    }

    /// Starts `agent` if it isn't running and waits until it's ready, first waiting for the check
    /// for agents, which comes after the app decides where agents run (the host or the app). Nil
    /// when it can't start (it isn't installed, or it failed), with `startFailure(of:)` saying why.
    @discardableResult
    func ensureRunning(_ agent: AgentDefinition.ID) async -> AgentRuntime? {
        // Runtimes for saved sessions exist from launch, but none may start before then.
        await agentsChecked()
        await agentRestarts[agent]?.value
        guard let runtime = runtimes[agent] else { return nil }
        if runtime.status == .idle {
            let environment = await launchEnvironment()
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

    /// How long one of the user's sessions sits unused (not shown, not working, no draft) before
    /// Native closes it, here and in the agent's process: the `sessionIdleTimeout` default
    /// (seconds) for every agent when it's set, else the agent's own `idleSessionTimeout`, else
    /// never. It's checked as often as agents are, so shorten `agentIdleTimeout` to try a short one.
    /// Only Claude Code sets its own (docs/performance.md): each of its sessions is a process.
    /// Codex is unloaded by the host instead (`idleUnloadTimeout`), which keeps the session open here.
    /// Reopening is faithful: a session loaded back gets its chosen settings set back
    /// (SessionModel+ConfigRestore.swift) and keeps Native's title.
    static func sessionIdleTimeout(for agent: AgentDefinition) -> Duration? {
        let seconds = UserDefaults.standard.double(forKey: "sessionIdleTimeout")
        if seconds > 0 { return .seconds(seconds) }
        return agent.manifest.idleSessionTimeout.map { .seconds($0) }
    }

    /// How long a session in Native's host sits with nothing happening before the host unloads it
    /// from the agent and, once none is loaded, ends the agent's process (`HostCore+IdleUnload.swift`):
    /// the `idleUnloadTimeout` default (seconds) for every agent when it's set, else the agent's own,
    /// else never. The session stays in the sidebar and its transcript stays put; it resumes quietly
    /// when it's next used.
    static func idleUnloadTimeout(for agent: AgentDefinition) -> Int? {
        let seconds = UserDefaults.standard.integer(forKey: "idleUnloadTimeout")
        return seconds > 0 ? seconds : agent.manifest.idleUnloadTimeout
    }

    /// Stops agents that sit unused for `agentIdleTimeout`, and closes sessions that sit unused for
    /// `sessionIdleTimeout(for:)`, for as long as the model lives. The default agent keeps running, so a
    /// new session never waits for one to start, and agents the host unloads itself are left to it.
    /// Internal only for AppModel.swift.
    func parkAgentsWhenIdle() {
        let timeout = Self.agentIdleTimeout
        let interval = min(.seconds(60), timeout / 5)
        Task { [weak self] in
            var idleSince: [AgentDefinition.ID: ContinuousClock.Instant] = [:]
            var sessionsIdleSince: [SessionKey: ContinuousClock.Instant] = [:]
            while true {
                try? await Task.sleep(for: interval, tolerance: interval / 10)
                guard let self else { return }
                let now = ContinuousClock.now
                closeIdleSessions(now: now, idleSince: &sessionsIdleSince)
                let defaultAgent = defaultAgent?.id
                for runtime in agents where runtime.isReady && !hostUnloadsIdle(runtime) {
                    let agent = runtime.agent.id
                    if agent == defaultAgent || isInUse(agent) {
                        idleSince[agent] = nil
                    } else if let since = idleSince[agent] {
                        if now - since >= timeout {
                            await park(runtime)
                            idleSince[agent] = nil
                        }
                    } else {
                        idleSince[agent] = now
                    }
                }
            }
        }
    }

    /// Closes the user's sessions that have been unused since `idleSince` for `sessionIdleTimeout`.
    /// Only ones the sidebar lists, so selecting one loads it back with `session/load`; task
    /// sessions belong to the engines that started them.
    private func closeIdleSessions(now: ContinuousClock.Instant, idleSince: inout [SessionKey: ContinuousClock.Instant])
    {
        var open: Set<SessionKey> = []
        for runtime in agents where runtime.isReady {
            guard let timeout = Self.sessionIdleTimeout(for: runtime.agent) else { continue }
            for session in sessions.open(of: runtime.agent.id)
            where session.root === session && session.origin == .user && catalog.lookup(session.key) != nil {
                open.insert(session.key)
                if isInUse(session) {
                    idleSince[session.key] = nil
                } else if let since = idleSince[session.key] {
                    if now - since >= timeout {
                        close(session, on: runtime)
                        idleSince[session.key] = nil
                    }
                } else {
                    idleSince[session.key] = now
                }
            }
        }
        idleSince = idleSince.filter { open.contains($0.key) }
    }

    private func close(_ session: SessionModel, on runtime: AgentRuntime) {
        Self.logger.info("Closing a \(runtime.agent.displayName, privacy: .public) session, unused for a while")
        guard session.host == nil else { return closeOnHost(session, on: runtime) }
        sessions.remove(session)
        guard runtime.capabilities?.closeSessions == true, let connection = runtime.connection else { return }
        let id = session.key.id
        Task { _ = try? await connection.send(CloseSessionRequest(sessionId: id)) }
    }

    /// Whether `session` or one of its subagents is busy, so closing it would lose something.
    private func isInUse(_ session: SessionModel) -> Bool {
        isBusy(session) || session.children.values.contains(where: isInUse)
    }

    /// Whether the host unloads `runtime`'s idle sessions and ends its process itself, keeping every
    /// transcript as it is, which parking here wouldn't.
    private func hostUnloadsIdle(_ runtime: AgentRuntime) -> Bool {
        runtime.host != nil && Self.idleUnloadTimeout(for: runtime.agent) != nil
            && runtime.capabilities?.closeSessions == true && runtime.capabilities?.resumeSessions == true
    }

    private func park(_ runtime: AgentRuntime) async {
        Self.logger.info("Stopping \(runtime.agent.displayName, privacy: .public), unused for a while")
        if runtime.host != nil {
            // The host keeps an agent that's working, whatever this app knows about it.
            guard await runtime.parkOnHost() else { return }
        } else {
            runtime.park()
        }
        sessions.removeAll(of: runtime.agent.id)
    }

    /// Whether stopping `agent` would lose something: a session it's starting or signing in for, a
    /// listing under way, or an open session (or the one that started it) that's busy, showing or
    /// holding a draft.
    private func isInUse(_ agent: AgentDefinition.ID) -> Bool {
        if startingTasks.contains(where: { $0.agent.id == agent && $0.failure == nil })
            || runtimes[agent]?.isSigningIn == true
            || listingsInFlight[agent, default: 0] > 0
        {
            return true
        }
        return sessions.open(of: agent).contains { isBusy($0) || isBusy($0.root) }
    }

    private func isBusy(_ session: SessionModel) -> Bool {
        session.key == selection || changingAgent?.candidate === session
            || session.phase == .loading || session.phase == .prompting
            || session.hasQueuedPrompts || session.isRetryScheduled || session.wait != nil || !session.draft.isEmpty
    }
}
