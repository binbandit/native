import Foundation
import Testing

@testable import ACP

/// The reason an approval shows under its headline: the agent's own words just before the call.
struct ToolReasonTests {
    private static func chunk(_ text: String, thought: Bool = false) -> String {
        #"{"jsonrpc":"2.0","method":"session/update","params":{"sessionId":"s","update":{"sessionUpdate":"\#(thought ? "agent_thought_chunk" : "agent_message_chunk")","content":{"type":"text","text":"\#(text)"}}}}"#
    }

    private static func call(_ id: String, input: String = #"{"command":"swift test"}"#) -> String {
        #"{"jsonrpc":"2.0","method":"session/update","params":{"sessionId":"s","update":{"sessionUpdate":"tool_call","toolCallId":"\#(id)","title":"swift test","kind":"execute","status":"pending","rawInput":\#(input)}}}"#
    }

    private static func state(_ lines: [String]) throws -> SessionState {
        var state = SessionState()
        state.appendUserMessage("Fix the flaky test")
        for line in lines { state.apply(try Wire.update(line)) }
        return state
    }

    @Test func lastParagraphBeforeTheCall() throws {
        let state = try Self.state([
            Self.chunk(
                "Reading the fixture first.\\n\\nIt fails about one run in five on CI, so I want to\\nsee it fail here."
            ),
            Self.chunk("Thinking about it", thought: true),
            Self.call("t1"),
        ])
        #expect(
            state.reason(forToolCall: "t1") == "It fails about one run in five on CI, so I want to see it fail here.")
    }

    @Test func noReasonWhenTheAgentWentStraightToTheCall() throws {
        let state = try Self.state([Self.chunk("Here's the plan."), Self.call("t1"), Self.call("t2")])
        #expect(state.reason(forToolCall: "t2") == nil)
        #expect(state.reason(forToolCall: "missing") == nil)
        let code = try Self.state([Self.chunk("Running:\\n\\n```sh\\nswift test\\n```"), Self.call("t3")])
        #expect(code.reason(forToolCall: "t3") == nil)
    }

    @Test func statedJustificationWins() throws {
        let state = try Self.state([
            Self.chunk("Let me run it."),
            Self.call(
                "t1", input: #"{"command":"swift test","justification":"Tests need the network to fetch fixtures."}"#),
        ])
        #expect(state.reason(forToolCall: "t1") == "Tests need the network to fetch fixtures.")
    }
}
