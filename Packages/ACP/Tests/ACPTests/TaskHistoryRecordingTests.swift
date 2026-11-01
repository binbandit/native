import Foundation
import Testing

@testable import ACP

/// A turn recorded for the task history from real traffic: what each agent would later be told.
struct TaskHistoryRecordingTests {
    /// The captured Claude Code turn (`Wire`), folded the way every client and the host fold it.
    private func capturedTurn() throws -> SessionState {
        var state = SessionState()
        state.appendUserMessage(Wire.promptText)
        for line in Wire.promptTurn {
            switch try Wire.event(line) {
            case .sessionUpdate(let notification): state.apply(notification.update)
            case .permissionRequest(let id, let request):
                state.requestPermission(request, id: id)
                state.resolvePermission(toolCallID: request.toolCall.toolCallId)
            case .elicitationRequest, .disconnected: Issue.record("Unexpected event")
            }
        }
        state.endTurn(try Wire.decode(PromptResponse.self, from: Wire.promptResult).stopReason)
        return state
    }

    @Test("A captured Claude Code turn records its tool calls and reply, without the prompt")
    func claudeTurn() throws {
        let state = try capturedTurn()
        let bodies = TaskHistoryRecording.bodies(state.items.dropFirst())
        guard bodies.count == 4, case .tool(let read) = bodies[0], case .tool(let write) = bodies[1],
            case .tool(let bash) = bodies[2], case .agent(let reply) = bodies[3]
        else {
            Issue.record("Expected three tool calls and a reply, got \(bodies)")
            return
        }
        #expect([read.id, write.id, bash.id] == [Wire.readToolCallID, Wire.writeToolCallID, Wire.bashToolCallID])
        #expect([read.kind, write.kind, bash.kind] == ["read", "edit", "execute"])
        #expect([read.status, write.status, bash.status] == ["completed", "completed", "completed"])
        #expect(write.paths == ["/private/tmp/acp-research/sandbox/out.txt"])
        #expect(bash.input == "ls")
        #expect(bash.output?.contains("notes.txt") == true)
        #expect(reply == Wire.agentMessage)
    }

    @Test("Recorded items survive the store's JSON round trip")
    func roundTrip() throws {
        let bodies = TaskHistoryRecording.bodies(try capturedTurn().items)
        let decoded = try bodies.map {
            try JSONDecoder().decode(TaskHistoryItem.Body.self, from: try JSONEncoder().encode($0))
        }
        #expect(decoded == bodies)
        #expect(decoded.first == .user(.init(text: Wire.promptText, origin: "user")))
    }

    @Test("A Codex exec call keeps its command; its output and long text are capped")
    func codexAndCaps() {
        var exec = CodexExecWire.call("call_1", "swift test")
        exec.content = [.content(.text(String(repeating: "x", count: 5_000)))]
        var thought = TranscriptMessage(role: .thought, text: String(repeating: "t", count: 5_000))
        thought.messageID = "r1"
        let bodies = TaskHistoryRecording.bodies([
            .toolCall(exec), .message(thought),
            .notice(TranscriptNotice(text: "Stopped.", isError: false)),
        ])
        guard bodies.count == 2, case .tool(let tool) = bodies[0], case .thought(let text) = bodies[1] else {
            Issue.record("Expected the call and the thought, got \(bodies)")
            return
        }
        #expect(tool.kind == "execute")
        #expect(tool.output?.hasSuffix("[Truncated]") == true)
        #expect(tool.output.map { $0.count <= TaskHistoryRecording.toolLimit + 20 } == true)
        #expect(text.count <= TaskHistoryRecording.thoughtLimit + 20)
    }

    @Test("A steered message keeps its flag; an empty reply is dropped")
    func steeredAndEmpty() {
        var steered = TranscriptMessage(role: .user, text: "also run the linter")
        steered.wasSteered = true
        let bodies = TaskHistoryRecording.bodies([
            .message(steered), .message(TranscriptMessage(role: .agent, text: "  ")),
        ])
        #expect(bodies == [.user(.init(text: "also run the linter", origin: "user", steered: true))])
        #expect(TaskHistoryRecording.plan([]) == nil)
    }
}
