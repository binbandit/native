import Testing

@testable import ACP

@Suite struct TurnFailureContextTests {
    @Test func usesLatestErrorFromCurrentTurn() {
        var state = SessionState()
        state.appendUserMessage("Move the host socket")
        state.appendNotice("Connection dropped", isError: true)
        state.appendNotice("Agent exited while linking", isError: true)
        state.endTurn(.error)
        let failure = TurnFailureContext(state: state)
        #expect(failure.details == "Agent exited while linking")
        #expect(failure.recovery == nil)
    }

    @Test func doesNotAttributeAnOlderRecoveryToThisTurn() {
        var state = SessionState()
        state.appendUserMessage("Earlier task")
        state.endTurn(.error)
        state.apply(.userMessageChunk(ContentChunk(content: .text(RecoveryPrompt(reason: .agentStopped).text))))
        state.appendNotice("Earlier failure", isError: true)
        state.endTurn(.error)
        state.appendUserMessage("Try the next step")
        #expect(TurnFailureContext(state: state) == TurnFailureContext(state: SessionState()))
    }

    @Test func reportsRecordedRecoveryWithoutInventingOne() {
        var state = SessionState()
        state.appendUserMessage("Move the host socket")
        state.endTurn(.error)
        state.apply(.userMessageChunk(ContentChunk(content: .text(RecoveryPrompt(reason: .agentStopped).text))))
        state.appendNotice("Agent exited again", isError: true)
        let failure = TurnFailureContext(state: state)
        #expect(failure.recovery?.contains("Native asked the agent to pick up where it left off") == true)
        #expect(failure.details == "Agent exited again")
    }
}
