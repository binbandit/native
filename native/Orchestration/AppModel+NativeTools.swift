extension AppModel {
    func setNativeMCPEnabled(_ enabled: Bool, for agent: AgentDefinition.ID) {
        plugins.setNativeMCPEnabled(enabled, for: agent)
        Task { await syncHostAgents() }
    }
}
