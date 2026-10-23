import Testing

@testable import TaskList

@Suite struct ConversationLinksTests {
    @Test func replacementPreservesBothDirectionsAndPersistence() {
        let result = ConversationLinks.replacing(
            "middle", with: "reloaded", in: ["middle": "first", "latest": "middle"],
            kept: ["middle", "latest"])
        #expect(result.links == ["reloaded": "first", "latest": "reloaded"])
        #expect(result.kept == ["reloaded", "latest"])
    }

    @Test func replacementDoesNotKeepAnUnsentConversation() {
        let result = ConversationLinks.replacing(
            "unsent", with: "reloaded", in: ["unsent": "earlier"], kept: [])
        #expect(result.links == ["reloaded": "earlier"])
        #expect(result.kept.isEmpty)
    }
}
