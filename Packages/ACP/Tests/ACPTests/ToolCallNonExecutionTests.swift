import Testing

@testable import ACP

struct ToolCallNonExecutionTests {
    static let callID = "toolu_01C1LuKrJBfHamY6UpPdUQhC"

    /// The live side of `InterruptionMarkerTests.toolUseReplay`: Claude Code announcing the command,
    /// then answering the user's stop while it ran (claude-agent-acp 0.93.0, Claude Code 2.1.304).
    /// Verbatim.
    static let live = [
        #"{"jsonrpc":"2.0","method":"session/update","params":{"sessionId":"70d2f58d-76b4-4808-a7b3-5cf33130f273","update":{"_meta":{"claudeCode":{"toolName":"Bash"}},"toolCallId":"toolu_01C1LuKrJBfHamY6UpPdUQhC","sessionUpdate":"tool_call","name":"Bash","rawInput":{},"status":"pending","title":"Terminal","kind":"execute","content":[]}}}"#,
        #"{"jsonrpc":"2.0","method":"session/update","params":{"sessionId":"70d2f58d-76b4-4808-a7b3-5cf33130f273","update":{"_meta":{"claudeCode":{"toolName":"Bash","nonExecutionKind":"user-rejected"}},"toolCallId":"toolu_01C1LuKrJBfHamY6UpPdUQhC","sessionUpdate":"tool_call_update","status":"failed","rawOutput":"The user doesn't want to proceed with this tool use. The tool use was rejected (eg. if it was a file edit, the new_string was NOT written to the file). STOP what you are doing and wait for the user to tell you how to proceed.","content":[{"type":"content","content":{"type":"text","text":"```\nThe user doesn't want to proceed with this tool use. The tool use was rejected (eg. if it was a file edit, the new_string was NOT written to the file). STOP what you are doing and wait for the user to tell you how to proceed.\n```"}}]}}}"#,
    ]

    private static func liveTurn(endingWith stopReason: StopReason) throws -> SessionState {
        var state = SessionState()
        state.appendUserMessage("Run `ping -c 40 127.0.0.1` with the Bash tool in the foreground")
        for line in live {
            state.apply(try Wire.update(line))
        }
        state.endTurn(stopReason)
        return state
    }

    @Test func aCommandTheUsersStopKilledIsStopped() throws {
        let call = try #require(try Self.liveTurn(endingWith: .cancelled).call(Self.callID))
        #expect(call.status == .cancelled)
        #expect(!call.wasRefused)
        // What Claude Code told its model stays with the call.
        #expect(call.rawOutput?.stringValue?.hasPrefix("The user doesn't want to proceed") == true)
    }

    @Test func aRefusalTheTurnCarriedOnFromStaysRefused() throws {
        let call = try #require(try Self.liveTurn(endingWith: .endTurn).call(Self.callID))
        #expect(call.status == .failed)
        #expect(call.wasRefused)
    }

    @Test func historyStopsTheCallsAToolUseStopCutOff() throws {
        var state = SessionState()
        for line in InterruptionMarkerTests.toolUseReplay {
            state.apply(try Wire.update(line))
        }
        #expect(state.call(Self.callID)?.status == .cancelled)
    }

    @Test func historyKeepsACallThatFailedBeforeTheStop() throws {
        // A hook blocked the command, then the user stopped the turn while Claude Code answered.
        var state = SessionState()
        for line in InterruptionMarkerTests.replay {
            state.apply(try Wire.update(line))
        }
        #expect(state.call("toolu_01J8i1Yg1DzXQb5KtUD5BKKX")?.status == .failed)
    }

    @Test func eachKindReadsAsItsAgentMeantIt() {
        func call(_ kind: String) -> ToolCallState? {
            var state = SessionState()
            var update = ToolCallUpdate(toolCallId: "c", title: "c", status: .failed)
            update.meta = .object(["claudeCode": .object(["nonExecutionKind": .string(kind)])])
            state.apply(.toolCall(update))
            return state.call("c")
        }
        #expect(call("interrupted")?.status == .cancelled)
        #expect(call("cancelled")?.status == .cancelled)
        #expect(call("permission-rule")?.wasRefused == true)
        #expect(call("automode-classifier")?.wasRefused == true)
        #expect(call("something-new")?.status == .failed)
        #expect(call("something-new")?.wasRefused == false)
    }
}

private extension SessionState {
    func call(_ id: String) -> ToolCallState? {
        items.lazy.compactMap { item -> ToolCallState? in
            if case .toolCall(let call) = item, call.id == id { call } else { nil }
        }.first
    }
}
