import ACP

/// Uses ACP's wire keys so its decoder remains the source of truth for cached choices.
struct AgentSavedConfigOption: Encodable {
    struct Choice: Encodable {
        let value: String
        let name: String
        let description: String?
    }
    let id: String
    let name: String
    let description: String?
    let category: String?
    let type = "select"
    let currentValue: String
    let options: [Choice]

    init?(_ option: ConfigOption) {
        guard case .select(let current, let choices) = option.kind else { return nil }
        id = option.id
        name = option.name
        description = option.description
        category = option.category
        currentValue = current
        options = choices.map { Choice(value: $0.value, name: $0.name, description: $0.description) }
    }
}
