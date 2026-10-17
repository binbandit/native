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
}
