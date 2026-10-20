import Foundation
import Testing

@testable import ACP

struct InterruptionMarkerTests {
    /// `session/load` of a Claude Code session whose first turn was stopped after a hook blocked its
    /// command, then given a second prompt (claude-agent-acp 0.93.0, Claude Code 2.1.304). Verbatim.
    static let replay = [
        #"{"jsonrpc":"2.0","method":"session/update","params":{"sessionId":"35174629-2442-405f-8d88-4742d79878f8","update":{"sessionUpdate":"user_message_chunk","content":{"type":"text","text":"Run `sleep 30` with the Bash tool, then reply with the single word done."},"messageId":"90ae68aa-e65e-4584-9056-7c00775b317a"}}}"#,
        #"{"jsonrpc":"2.0","method":"session/update","params":{"sessionId":"35174629-2442-405f-8d88-4742d79878f8","update":{"_meta":{"claudeCode":{"toolName":"Bash"}},"toolCallId":"toolu_01J8i1Yg1DzXQb5KtUD5BKKX","sessionUpdate":"tool_call","name":"Bash","rawInput":{"command":"sleep 30","description":"Sleep for 30 seconds"},"status":"pending","title":"sleep 30","kind":"execute","content":[{"type":"content","content":{"type":"text","text":"Sleep for 30 seconds"}}]}}}"#,
        #"{"jsonrpc":"2.0","method":"session/update","params":{"sessionId":"35174629-2442-405f-8d88-4742d79878f8","update":{"_meta":{"claudeCode":{"toolName":"Bash"}},"toolCallId":"toolu_01J8i1Yg1DzXQb5KtUD5BKKX","sessionUpdate":"tool_call_update","status":"failed","rawOutput":"<tool_use_error>Blocked: standalone sleep 30. To wait for a condition, use Monitor with an until-loop (e.g. `until <check>; do sleep 2; done`). To wait for a command you started, use run_in_background: true. Do not chain shorter sleeps to work around this block.</tool_use_error>","content":[{"type":"content","content":{"type":"text","text":"```\n<tool_use_error>Blocked: standalone sleep 30. To wait for a condition, use Monitor with an until-loop (e.g. `until <check>; do sleep 2; done`). To wait for a command you started, use run_in_background: true. Do not chain shorter sleeps to work around this block.</tool_use_error>\n```"}}]}}}"#,
        #"{"jsonrpc":"2.0","method":"session/update","params":{"sessionId":"35174629-2442-405f-8d88-4742d79878f8","update":{"sessionUpdate":"user_message_chunk","content":{"type":"text","text":"[Request interrupted by user]"},"messageId":"10f12804-a839-4c20-89cd-eedf59213edc"}}}"#,
        #"{"jsonrpc":"2.0","method":"session/update","params":{"sessionId":"35174629-2442-405f-8d88-4742d79878f8","update":{"sessionUpdate":"user_message_chunk","content":{"type":"text","text":"Reply with the single word ok."},"messageId":"8b24a88f-5307-491a-98da-8a9c776055a8"}}}"#,
        #"{"jsonrpc":"2.0","method":"session/update","params":{"sessionId":"35174629-2442-405f-8d88-4742d79878f8","update":{"sessionUpdate":"agent_message_chunk","content":{"type":"text","text":"ok"},"messageId":"msg_011CgCmUPbK2KHpEDHXt6w6S"}}}"#,
    ]

    /// `session/load` of one stopped while its command ran (same versions). Verbatim.
    static let toolUseReplay = [
        #"{"jsonrpc":"2.0","method":"session/update","params":{"sessionId":"70d2f58d-76b4-4808-a7b3-5cf33130f273","update":{"sessionUpdate":"user_message_chunk","content":{"type":"text","text":"Run `ping -c 40 127.0.0.1` with the Bash tool in the foreground, then reply with the single word done."},"messageId":"256cd8e0-2fc6-4fa3-84f1-b0cd97de6acc"}}}"#,
        #"{"jsonrpc":"2.0","method":"session/update","params":{"sessionId":"70d2f58d-76b4-4808-a7b3-5cf33130f273","update":{"_meta":{"claudeCode":{"toolName":"Bash"}},"toolCallId":"toolu_01C1LuKrJBfHamY6UpPdUQhC","sessionUpdate":"tool_call","name":"Bash","rawInput":{"command":"ping -c 40 127.0.0.1","description":"Ping localhost 40 times in foreground","timeout":120000},"status":"pending","title":"ping -c 40 127.0.0.1","kind":"execute","content":[{"type":"content","content":{"type":"text","text":"Ping localhost 40 times in foreground"}}]}}}"#,
        #"{"jsonrpc":"2.0","method":"session/update","params":{"sessionId":"70d2f58d-76b4-4808-a7b3-5cf33130f273","update":{"_meta":{"claudeCode":{"toolName":"Bash"}},"toolCallId":"toolu_01C1LuKrJBfHamY6UpPdUQhC","sessionUpdate":"tool_call_update","status":"failed","rawOutput":"The user doesn't want to proceed with this tool use. The tool use was rejected (eg. if it was a file edit, the new_string was NOT written to the file). STOP what you are doing and wait for the user to tell you how to proceed.","content":[{"type":"content","content":{"type":"text","text":"```\nThe user doesn't want to proceed with this tool use. The tool use was rejected (eg. if it was a file edit, the new_string was NOT written to the file). STOP what you are doing and wait for the user to tell you how to proceed.\n```"}}]}}}"#,
        #"{"jsonrpc":"2.0","method":"session/update","params":{"sessionId":"70d2f58d-76b4-4808-a7b3-5cf33130f273","update":{"sessionUpdate":"user_message_chunk","content":{"type":"text","text":"[Request interrupted by user for tool use]"},"messageId":"8b0160e3-202a-49e6-8882-977e54a74bd0"}}}"#,
    ]

    @Test func replayedStopEndsItsTurnInsteadOfShowingAsAPrompt() throws {
        var state = SessionState()
        for line in Self.replay {
            state.apply(try Wire.update(line))
        }

        #expect(
            state.userTexts == [
                "Run `sleep 30` with the Bash tool, then reply with the single word done.",
                "Reply with the single word ok.",
            ])
        #expect(state.notices.map(\.text) == ["Stopped."])
        #expect(state.notices.map(\.isError) == [false])
        // The stop closes the first turn, like a live one; it doesn't start a turn of its own.
        let turns = state.turns
        #expect(turns.count == 2)
        #expect(turns.map(\.stopReason) == [.cancelled, nil])
        #expect(state.items[turns[0].items].last?.id == state.notices.first.map { TranscriptItem.notice($0).id })
    }

    @Test func aStopDuringAToolCallCountsToo() throws {
        var state = SessionState()
        for line in Self.toolUseReplay {
            state.apply(try Wire.update(line))
        }
        #expect(
            state.userTexts == [
                "Run `ping -c 40 127.0.0.1` with the Bash tool in the foreground, then reply with the single word done."
            ])
        #expect(state.notices.map(\.text) == ["Stopped."])
        #expect(state.turns.map(\.stopReason) == [.cancelled])
    }

    @Test func promptsThatOnlyQuoteTheMarkerStayTheUsers() {
        var state = SessionState()
        for text in [
            "Why did I see [Request interrupted by user] earlier?", "[Request interrupted by user] ",
            "[request interrupted by user]",
        ] {
            state.apply(userChunk(text, id: UUID().uuidString))
        }
        // Typed live, even the exact text is the user's: only replayed history carries the agent's.
        state.appendUserMessage("[Request interrupted by user]")
        #expect(state.userTexts.count == 4)
        #expect(state.notices.isEmpty)
    }

    @Test func aLiveTurnReportsItsOwnStop() {
        var state = SessionState()
        state.appendUserMessage("Run the tests")
        state.apply(userChunk("[Request interrupted by user]", id: "u1"))
        state.endTurn(.cancelled)
        state.apply(userChunk("[Request interrupted by user]", id: "u2"))
        #expect(state.notices.map(\.text) == ["Stopped."])
        #expect(state.userTexts == ["Run the tests"])
    }
}

private func userChunk(_ text: String, id: String) -> SessionUpdate {
    .userMessageChunk(ContentChunk(content: .text(text), messageId: id))
}

private extension SessionState {
    var userTexts: [String] {
        items.compactMap { item in
            if case .message(let message) = item, message.role == .user { message.text } else { nil }
        }
    }

    var notices: [TranscriptNotice] {
        items.compactMap { item in
            if case .notice(let notice) = item { notice } else { nil }
        }
    }
}
