import Testing

@testable import ACP

@Suite struct AgentModelGroupingTests {
    struct Model: Equatable, Sendable {
        let agent: String
        let choice: ConfigOption.SelectOption
    }

    let catalog: [Model] = [
        .init(agent: "claude", choice: .init(value: "shared", name: "Haiku")),
        .init(agent: "codex", choice: .init(value: "shared", name: "Sol")),
        .init(agent: "claude", choice: .init(value: "opus", name: "Opus")),
        .init(agent: "copilot", choice: .init(value: "auto", name: "Auto")),
        .init(agent: "cursor", choice: .init(value: "auto", name: "Auto")),
    ]

    @Test func twoAndFourAgentsKeepTheirFirstSeenOrder() {
        let groups = AgentModelGroups(catalog, agent: \.agent)
        #expect(groups.groups.map(\.id) == ["claude", "codex", "copilot", "cursor"])
        #expect(groups.models(for: "claude").map(\.choice.value) == ["shared", "opus"])
        let two = AgentModelGroups(Array(catalog.prefix(3)), agent: \.agent)
        #expect(two.groups.map(\.id) == ["claude", "codex"])
    }

    @Test func filteringCannotMatchAnotherAgentsModels() {
        let groups = AgentModelGroups(catalog, agent: \.agent)
        let filtered = ModelChoiceList(
            choices: groups.models(for: "claude").map(\.choice), current: "shared", query: "Sol", forceFilter: true)
        #expect(filtered.rows.isEmpty)
        let empty = AgentModelGroups<String, Model>([], agent: \.agent)
        #expect(empty.groups.isEmpty)
    }

    @Test func switchingChangesTheModelScope() {
        let groups = AgentModelGroups(catalog, agent: \.agent)
        let list = ModelChoiceList(choices: groups.models(for: "claude").map(\.choice), current: "shared")
        #expect(list.rows.map(\.name) == ["Haiku", "Opus"])
        let switched = ModelChoiceList(choices: groups.models(for: "codex").map(\.choice), current: "shared")
        #expect(switched.rows.map(\.name) == ["Sol"])
        #expect(groups.models(for: "missing").isEmpty)
    }
}
