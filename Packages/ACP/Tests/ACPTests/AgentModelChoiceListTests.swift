import Testing

@testable import ACP

@Suite struct AgentModelChoiceListTests {
    @Test func agentMatchingRetainsAdapterOrderAndIdentity() {
        let choices = (0..<10).map { ConfigOption.SelectOption(value: "model-\($0)", name: "Model \($0)") }
        let terms = Dictionary(
            uniqueKeysWithValues: choices.enumerated().map {
                ($0.element.value, [$0.offset < 4 ? "Claude Code" : "Codex"])
            })
        let list = ModelChoiceList(choices: choices, current: "model-0", query: "codex", searchTerms: terms)
        #expect(list.rows.map(\.id) == Array(choices.dropFirst(4)).map(\.value))
        #expect(list.overflow == 0)
        #expect(list.rows.allSatisfy { $0.name.hasPrefix("Model") })
    }

    @Test func heightLimitedCatalogRemainsFullyReachable() {
        let choices = (0..<8).map { ConfigOption.SelectOption(value: "\($0)", name: "Model \($0)") }
        let initial = ModelChoiceList(choices: choices, current: "7", slots: 5, forceFilter: true)
        #expect(initial.isFilterable)
        #expect(initial.rows.map(\.id) == ["0", "1", "2", "3", "7"])
        let filtered = ModelChoiceList(choices: choices, current: "7", query: "6", slots: 5, forceFilter: true)
        #expect(filtered.rows.map(\.id) == ["6"])
        #expect(
            ModelChoiceList(choices: choices, current: "7", query: "nebula", slots: 5, forceFilter: true).rows.isEmpty)
    }
}
