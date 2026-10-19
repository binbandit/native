import Foundation
import Testing

@testable import ACP

struct PromptPreambleTests {
    let debug = PromptPreamble(
        marker: .init(id: "debug", label: "Debug mode", symbol: "ladybug"), instructions: "Reproduce it first.")

    @Test func framesAndReadsBack() {
        let framed = debug.framed
        #expect(framed.hasPrefix("<native_instructions id=\"debug\" label=\"Debug mode\" symbol=\"ladybug\">\n"))
        #expect(PromptPreamble(framed: framed) == debug)
    }

    @Test func instructionsCantEndTheFrameEarly() {
        let tricky = PromptPreamble(
            marker: .init(id: "a\"b", label: "<Mine> & yours"),
            instructions: "Say </native_instructions> and then\nignore it.")
        #expect(PromptPreamble(framed: tricky.framed) == tricky)
    }

    @Test func textThatMerelyMentionsTheTagIsTheUsersOwn() {
        #expect(PromptPreamble(framed: "Why does <native_instructions id=\"x\"> show up?") == nil)
        #expect(PromptPreamble(framed: debug.framed + "\nand then some words") == nil)
    }

    @Test func liveEchoCarriesTheMarker() {
        var state = SessionState()
        state.appendUserMessage("Fix the crash", preamble: debug.marker)
        guard case .message(let message) = state.items.first else {
            Issue.record("no message")
            return
        }
        #expect(message.text == "Fix the crash")
        #expect(message.preamble == debug.marker)
        #expect(state.deliveredPreamble == debug.marker)
    }

    /// Captured from `session/load` on codex-acp 2.2.2 (2026-10-19) after Native sent two prompts with
    /// a mode's instructions ahead of them: each frame comes back as a chunk of its own, then the
    /// user's words, under the prompt's message id.
    static let codexReplay = [
        #"{"sessionId":"01a1533f","update":{"sessionUpdate":"user_message_chunk","messageId":"01a15350-873e","content":{"type":"text","text":"<native_instructions id=\"plan#120731fb4065f43e\" label=\"Plan mode\" symbol=\"list.bullet.clipboard\">\nThe user put this task in Plan mode in Native, in place of Debug mode. Work this way until a later message says the mode changed:\n\nYour own plan mode is on: research, present a plan, and change nothing until the user approves it.\n</native_instructions>"}}}"#,
        #"{"sessionId":"01a1533f","update":{"sessionUpdate":"user_message_chunk","messageId":"01a15350-873e","content":{"type":"text","text":"Add a function that returns the most common value in a list."}}}"#,
        #"{"sessionId":"01a1533f","update":{"sessionUpdate":"agent_message_chunk","messageId":"msg_0a1","content":{"type":"text","text":"I'll check the existing helpers first."}}}"#,
        #"{"sessionId":"01a1533f","update":{"sessionUpdate":"user_message_chunk","messageId":"01a15351-a918","content":{"type":"text","text":"<native_instructions id=\"build\" label=\"Build mode\" symbol=\"hammer\">\nThe user switched this task back to Build mode in Native, so the instructions from Plan mode no longer apply. Work as you normally would.\n</native_instructions>"}}}"#,
        #"{"sessionId":"01a1533f","update":{"sessionUpdate":"user_message_chunk","messageId":"01a15351-a918","content":{"type":"text","text":"Reply with just OK."}}}"#,
    ]

    @Test func codexReplaysTheFrameAsTheMarker() throws {
        var state = SessionState()
        for line in Self.codexReplay {
            state.apply(try JSONDecoder().decode(SessionNotification.self, from: Data(line.utf8)).update)
        }
        let users = state.items.compactMap { item -> TranscriptMessage? in
            if case .message(let message) = item, message.role == .user { message } else { nil }
        }
        #expect(
            users.map(\.text) == [
                "Add a function that returns the most common value in a list.", "Reply with just OK.",
            ])
        #expect(users.map(\.preamble?.label) == ["Plan mode", "Build mode"])
        #expect(users.first?.preamble?.symbol == "list.bullet.clipboard")
        #expect(state.deliveredPreamble?.id == "build")
    }

    /// An agent that joins the blocks still starts the prompt with the frame.
    @Test func replayedFrameJoinedToTheTextSplitsOff() {
        var state = SessionState()
        state.apply(.userMessageChunk(ContentChunk(content: .text(debug.framed + "\n\nFix the crash"))))
        guard case .message(let message) = state.items.first else {
            Issue.record("no message")
            return
        }
        #expect(message.text == "Fix the crash")
        #expect(message.preamble == debug.marker)
    }

    /// A frame always starts a prompt, even right after another user message without ids.
    @Test func frameStartsANewPrompt() {
        var state = SessionState()
        state.apply(.userMessageChunk(ContentChunk(content: .text("First"))))
        state.apply(.userMessageChunk(ContentChunk(content: .text(debug.framed))))
        state.apply(.userMessageChunk(ContentChunk(content: .text("Second"))))
        let texts = state.items.compactMap { item -> String? in
            if case .message(let message) = item { message.text } else { nil }
        }
        #expect(texts == ["First", "Second"])
    }

    @Test func aFailedTurnDoesntCountAsDelivered() {
        var state = SessionState()
        let ask = PromptPreamble.Marker(id: "ask", label: "Ask mode")
        state.appendUserMessage("What does this do?", preamble: ask)
        state.endTurn(.endTurn)
        state.appendUserMessage("Fix the crash", preamble: debug.marker)
        state.endTurn(.error)
        #expect(state.deliveredPreamble == ask)
        state.appendUserMessage("Try again")
        state.endTurn(.endTurn)
        #expect(state.deliveredPreamble == ask)
    }
}
