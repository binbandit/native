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

    /// Agents replay the frame as a text chunk of its own, then the user's words with the same id.
    @Test func replayedFrameBecomesTheMarker() throws {
        var state = SessionState()
        state.apply(.userMessageChunk(ContentChunk(content: .text(debug.framed), messageId: "m1")))
        state.apply(.userMessageChunk(ContentChunk(content: .text("Fix the crash"), messageId: "m1")))
        state.apply(.agentMessageChunk(ContentChunk(content: .text("On it."), messageId: "m2")))
        let users = state.items.compactMap { item -> TranscriptMessage? in
            if case .message(let message) = item, message.role == .user { message } else { nil }
        }
        #expect(users.map(\.text) == ["Fix the crash"])
        #expect(users.first?.preamble == debug.marker)
        #expect(state.deliveredPreamble == debug.marker)
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
