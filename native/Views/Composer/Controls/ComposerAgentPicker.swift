import ACP

/// The installed agents, their live availability and the model action shared by legacy controls.
struct ComposerAgentPicker {
    let models: [ComposerAgentModel]
    let current: AgentDefinition.ID
    var pending: AgentDefinition.ID?
    var showsLoader = false
    var highlightsAgent = false
    let onChoose: (AgentDefinition.ID) -> Void

    var agents: [ComposerAgentModel] {
        AgentModelGroups(models, agent: \.agent).groups.compactMap { $0.models.first }
    }
}
