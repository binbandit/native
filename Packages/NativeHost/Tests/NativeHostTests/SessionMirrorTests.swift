import ACP
import Foundation
import NativeHostProtocol
import Testing

@Suite("Session mirror")
struct SessionMirrorTests {
    private func chunk(_ kind: String, _ text: String, id: String? = nil) -> HostEvent.Payload {
        var update: [String: JSONValue] = ["sessionUpdate": .string(kind), "content": .object(["type": .string("text"), "text": .string(text)])]
        update["messageId"] = id.map(JSONValue.string)
        return .update(.object(update))
    }

    @Test("Folds a turn into the same transcript ACP's reducer builds")
    func foldsATurn() {
        var mirror = SessionMirror()
        mirror.apply([
            HostEvent(seq: 1, payload: .reset(loading: false)),
            HostEvent(seq: 2, payload: .prompt(PromptEcho(text: "Hello"))),
            HostEvent(seq: 3, payload: chunk("agent_message_chunk", "Hi ")),
            HostEvent(seq: 4, payload: chunk("agent_message_chunk", "there")),
            HostEvent(seq: 5, payload: .turnEnded(stopReason: "end_turn")),
        ])
        #expect(mirror.userMessages == ["Hello"])
        guard case .message(let reply)? = mirror.state.items.last else {
            Issue.record("Expected the agent's reply last")
            return
        }
        #expect(reply.text == "Hi there")
        #expect(mirror.lastSeq == 5)
    }

    @Test("Seen events are skipped, but a reset always starts over")
    func dedupeAndReset() {
        var mirror = SessionMirror()
        let prompt = HostEvent(seq: 2, payload: .prompt(PromptEcho(text: "Once")))
        mirror.apply([HostEvent(seq: 1, payload: .reset(loading: false)), prompt, prompt])
        #expect(mirror.userMessages == ["Once"])
        // A restarted host numbers from 1 again, starting with its reset.
        mirror.apply([HostEvent(seq: 1, payload: .reset(loading: true)), HostEvent(seq: 2, payload: chunk("user_message_chunk", "Replayed", id: "m0"))])
        #expect(mirror.isLoading)
        #expect(mirror.userMessages == ["Replayed"])
        mirror.apply(HostEvent(seq: 3, payload: .loaded))
        #expect(!mirror.isLoading)
    }

    @Test("Permission requests show until resolved by any client")
    func permissions() {
        let request = JSONValue.object([
            "sessionId": .string("s"),
            "toolCall": .object(["toolCallId": .string("call-1"), "title": .string("Write notes.txt")]),
            "options": .array([.object(["optionId": .string("allow"), "name": .string("Allow"), "kind": .string("allow_once")])]),
        ])
        var mirror = SessionMirror()
        mirror.apply(HostEvent(seq: 1, payload: .permissionRequested(toolCallID: "call-1", request: request)))
        #expect(mirror.state.pendingPermissions.map(\.toolCallID) == ["call-1"])
        mirror.apply(HostEvent(seq: 2, payload: .permissionResolved(toolCallID: "call-1", optionID: "allow")))
        #expect(mirror.state.pendingPermissions.isEmpty)
    }

    @Test("A recovery shows as a notice saying what Native did")
    func recoveryNotice() {
        var mirror = SessionMirror()
        let note = RecoveryNote(cause: .agentStopped, action: .resumed, agentName: "Codex", interruptedAt: .now)
        mirror.apply(HostEvent(seq: 1, payload: .recovered(note)))
        guard case .notice(let notice)? = mirror.state.items.last else {
            Issue.record("Expected a notice")
            return
        }
        #expect(notice.text.hasPrefix("Codex stopped unexpectedly"))
        #expect(!notice.isError)
    }
}
