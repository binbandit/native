extension AppModel {
    /// Enabled agents that aren't installed: what Add Agent offers.
    var agentsToAdd: [AgentDefinition] {
        installations.notInstalled(plugins.agents)
    }

    /// Where an agent stands, from not installed to ready, for any view that shows one.
    func availability(of agent: AgentDefinition) -> AgentAvailability {
        AgentAvailability(
            installation: installations[agent.id],
            isEnabled: plugins.isEnabled(agent.pluginID),
            runtime: runtimes[agent.id]
        )
    }

    /// After signing in from a terminal: restarts the agent with a fresh environment so it picks up
    /// the login, then starts the session the user was starting, if it no longer needs a sign-in.
    func finishTerminalSignIn(_ request: AgentTerminalSignIn) async {
        let agent = request.agent.id
        await restart(agent)
        guard request.startsSession, let runtime = runtime(agent), runtime.isReady, !runtime.needsSignIn else { return }
        await newSession(with: agent)
    }
}
