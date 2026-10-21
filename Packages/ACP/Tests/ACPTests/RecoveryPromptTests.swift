import Foundation
import Testing

@testable import ACP

@Suite("Native's recovery prompt in an agent's history")
struct RecoveryPromptTests {
    /// codex-acp 2.2.2 replaying a session whose host was killed while a command ran (from a capture
    /// on 2026-10-20, ids and output shortened), up to Native's prompt telling it so.
    private let replay = [
        #"{"jsonrpc":"2.0","method":"session/update","params":{"sessionId":"s","update":{"sessionUpdate":"user_message_chunk","messageId":"u1","content":{"type":"text","text":"Run the same command once more, then reply with only its last line."}}}}"#,
        #"{"jsonrpc":"2.0","method":"session/update","params":{"sessionId":"s","update":{"sessionUpdate":"tool_call","toolCallId":"exec-1","name":"exec_command","kind":"execute","title":"for i in $(seq 1 45); do echo tick $i; sleep 1; done","status":"failed","content":[{"type":"terminal","terminalId":"exec-1"}]}}}"#,
        #"{"jsonrpc":"2.0","method":"session/update","params":{"sessionId":"s","update":{"sessionUpdate":"tool_call_update","toolCallId":"exec-1","_meta":{"terminal_output_delta":{"data":"tick 1\n","terminal_id":"exec-1"},"terminal_exit":{"exit_code":-1,"signal":null,"terminal_id":"exec-1"}}}}}"#,
    ]
    private let answer = SessionUpdate.agentMessageChunk(
        ContentChunk(content: .text("I'll check whether it finished.")))

    private func userChunk(_ text: String) -> SessionUpdate {
        .userMessageChunk(ContentChunk(content: .text(text), messageId: "u2"))
    }

    @Test("It shows as what Native told the agent, and the interrupted turn carries on as it did live")
    func replayedPromptIsNatives() throws {
        var state = SessionState()
        for line in replay {
            state.apply(try Wire.update(line))
        }
        let sent = RecoveryPrompt(reason: .hostStopped).text
        state.apply(userChunk(sent))
        state.apply(answer)
        state.endReplay()

        #expect(state.turns.count == 1)
        let users = state.items.compactMap { item -> String? in
            if case .message(let message) = item, message.role == .user { message.text } else { nil }
        }
        #expect(users == ["Run the same command once more, then reply with only its last line."])
        guard case .toolCall(let call) = state.items[1], case .notice(let notice) = state.items[2] else {
            Issue.record("Expected the command, then Native's notice")
            return
        }
        #expect(call.status == .interrupted)
        #expect(
            notice.text
                == "This turn was interrupted because Native's background host stopped unexpectedly. Native asked the agent to pick up where it left off."
        )
        #expect(!notice.isError)
        #expect(notice.sentToAgent == sent)
    }

    @Test("Every reason Native sends is recognized", arguments: RecoveryPrompt.Reason.allCases)
    func everyReason(_ reason: RecoveryPrompt.Reason) {
        #expect(RecoveryPrompt(replayed: RecoveryPrompt(reason: reason).text)?.reason == reason)
    }

    @Test("A reason from a newer Native still reads as Native's")
    func unknownReason() {
        let prompt = RecoveryPrompt(replayed: "[Native] Your previous turn was interrupted because of a solar flare.")
        #expect(prompt != nil)
        #expect(prompt?.reason == nil)
        #expect(prompt?.notice == "This turn was interrupted. Native asked the agent to pick up where it left off.")
    }

    @Test("A user's message that only quotes it stays the user's")
    func quotedStaysTheUsers() {
        var state = SessionState()
        state.apply(userChunk("Why did you get \"[Native] Your previous turn was interrupted\" earlier?"))
        #expect(state.turns.count == 1)
        guard case .message(let message)? = state.items.first else {
            Issue.record("Expected the user's message")
            return
        }
        #expect(message.role == .user)
    }

    @Test("Live, Native's prompt never reaches the transcript, so nothing is recognized mid-turn")
    func liveTurnIsUntouched() {
        var state = SessionState()
        state.appendUserMessage("Go")
        state.apply(userChunk(RecoveryPrompt(reason: .agentStopped).text))
        #expect(state.items.count == 2)
    }

    @Test(
        "A stop after recovery settles only the resumed work even if the earlier process recorded a stop",
        arguments: [true, false])
    func stopAfterRecovery(withAnswer: Bool) throws {
        var state = SessionState()
        for line in InterruptionMarkerTests.replay.prefix(4) {
            state.apply(try Wire.update(line))
        }
        state.apply(userChunk(RecoveryPrompt(reason: .agentStopped).text))
        if withAnswer { state.apply(answer) }
        for line in InterruptionMarkerTests.toolUseReplay.dropFirst() {
            state.apply(try Wire.update(line))
        }
        // Repeating the same segment's stop still adds nothing.
        state.apply(userChunk("[Request interrupted by user for tool use]"))
        state.endReplay()

        let stops = state.items.compactMap { item -> String? in
            if case .notice(let notice) = item, notice.text == "Stopped." { notice.text } else { nil }
        }
        let calls = state.items.compactMap { item -> ToolCallState? in
            if case .toolCall(let call) = item { call } else { nil }
        }
        #expect(stops.count == 2)
        #expect(calls.first?.status == .failed)
        #expect(calls.last?.status == .cancelled)
        #expect(state.turns.count == 1)
        #expect(state.turns.first?.stopReason == .cancelled)
    }

    @Test("A recovery that finishes no longer has the preceding interruption's stop reason")
    func finishedRecoveryClearsEarlierStop() throws {
        var state = SessionState()
        for line in InterruptionMarkerTests.replay.prefix(4) {
            state.apply(try Wire.update(line))
        }
        state.apply(userChunk(RecoveryPrompt(reason: .agentStopped).text))
        state.apply(answer)
        state.endReplay()

        #expect(state.turns.count == 1)
        #expect(state.turns.first?.stopReason == nil)
    }
}
