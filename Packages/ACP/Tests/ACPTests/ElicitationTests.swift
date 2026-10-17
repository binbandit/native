import Foundation
import Testing
@testable import ACP

/// Claude Code's AskUserQuestion as claude-agent-acp 0.93 sends it to a client that advertises form
/// elicitation (captured from a real session).
struct ElicitationTests {
    static let askUserQuestion = #"""
        {"jsonrpc": "2.0", "id": 0, "method": "elicitation/create", "params": {"mode": "form", "sessionId": "7976b558-a38b-4b72-b10a-cc3ac9fc2c4d", "toolCallId": "toolu_016PGc48eyfVKaczjHf1iguq", "message": "Which color do you prefer?", "requestedSchema": {"type": "object", "properties": {"question_0": {"type": "string", "title": "Color", "oneOf": [{"const": "Red", "title": "Red", "description": "A warm, bold color"}, {"const": "Blue", "title": "Blue", "description": "A cool, calm color"}]}, "question_0_custom": {"type": "string", "title": "Other", "description": "Type your own answer, or add a note to the option you chose above (optional)."}}}}}
        """#

    @Test func askUserQuestionArrivesAsAFormElicitation() throws {
        guard case .elicitationRequest(let id, let request) = try Wire.event(Self.askUserQuestion) else {
            Issue.record("Expected an elicitation request")
            return
        }
        #expect(id == .int(0))
        #expect(request.sessionId == SessionID("7976b558-a38b-4b72-b10a-cc3ac9fc2c4d"))
        #expect(request.mode == .form)
        #expect(request.toolCallId == "toolu_016PGc48eyfVKaczjHf1iguq")
        #expect(request.message == "Which color do you prefer?")
        guard case .array(let options)? = request.requestedSchema?["properties"]?["question_0"]?["oneOf"] else {
            Issue.record("Expected the question's options")
            return
        }
        #expect(options.compactMap { $0["const"]?.stringValue } == ["Red", "Blue"])
        #expect(request.requestedSchema?["properties"]?["question_0_custom"]?["title"]?.stringValue == "Other")
    }

    @Test func unknownModesDecodeAsUnsupported() throws {
        let request = try Wire.decode(CreateElicitationRequest.self, from: #"{"sessionId": "s", "mode": "openai/form", "message": "?"}"#)
        #expect(request.mode == .unsupported("openai/form"))
        #expect(request.requestedSchema == nil)
    }

    @Test func responsesEncodeTheirAction() throws {
        // The answer Claude Code folds back into the tool's input as {"Which color do you prefer?": "Red"}.
        #expect(try encoded(.accept(content: ["question_0": .string("Red")])) == #"{"action":"accept","content":{"question_0":"Red"}}"#)
        #expect(try encoded(.decline) == #"{"action":"decline"}"#)
        #expect(try encoded(.cancel) == #"{"action":"cancel"}"#)
    }

    private func encoded(_ response: CreateElicitationResponse) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        return String(decoding: try encoder.encode(response), as: UTF8.self)
    }
}
