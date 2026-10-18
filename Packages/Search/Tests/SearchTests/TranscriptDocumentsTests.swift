import ACP
import Foundation
import Testing

@testable import Search

struct TranscriptDocumentsTests {
    private func update(_ json: String) throws -> SessionUpdate {
        try JSONDecoder().decode(SessionUpdate.self, from: Data(json.utf8))
    }

    private func transcript() throws -> SessionState {
        var state = SessionState()
        try state.apply(
            update(#"{"sessionUpdate":"user_message_chunk","content":{"type":"text","text":"Rename   the\nstore"}}"#))
        try state.apply(update(#"{"sessionUpdate":"agent_message_chunk","content":{"type":"text","text":"On "}}"#))
        try state.apply(update(#"{"sessionUpdate":"agent_message_chunk","content":{"type":"text","text":"it."}}"#))
        try state.apply(
            update(
                #"{"sessionUpdate":"tool_call","toolCallId":"toolu_9","title":"Edit SessionStore.swift","kind":"edit","status":"completed","content":[{"type":"diff","path":"/r/SessionStore.swift","oldText":"a","newText":"struct Store {}"}],"rawInput":{"file_path":"/r/SessionStore.swift"}}"#
            ))
        return state
    }

    @Test func liveTranscriptBecomesDocuments() throws {
        let documents = SearchDocument.documents(transcript: try transcript().items)
        #expect(documents.map(\.role) == [.user, .agent, .tool])
        #expect(documents[1].text == "On it.")
        #expect(documents[2].hasDiff)
        #expect(documents[2].text.contains("/r/SessionStore.swift"))
        #expect(documents[2].text.contains("struct Store {}"))
    }

    @Test func anchorsFindTheirItemsAgain() throws {
        let items = try transcript().items
        #expect(SearchAnchor.toolCall(id: "toolu_9").index(in: items) == 2)
        #expect(SearchAnchor.message(startingWith: "Rename the store").index(in: items) == 0)
        #expect(SearchAnchor.message(startingWith: "On it.").index(in: items) == 1)
        #expect(SearchAnchor.session.index(in: items) == nil)
    }
}
