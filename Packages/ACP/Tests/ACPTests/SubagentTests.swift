import Foundation
import Testing

@testable import ACP

struct SubagentTests {
    // MARK: - Decoding

    @Test func announcementAndIdleUpdatesDecode() throws {
        guard case .subagent(let announced) = try Wire.update(SubagentWire.running),
            case .subagent(let finished) = try Wire.update(SubagentWire.idle)
        else {
            Issue.record("Expected subagent updates")
            return
        }
        #expect(announced.sessionId == SubagentWire.childID)
        #expect(announced.title == .set("general-purpose"))
        #expect(announced.description == .set("Reply with hi"))
        #expect(announced.canCancel == .set(true))
        #expect(announced.state == .set(.running))

        // The idle update carries only the new state.
        #expect(finished.title == .unchanged)
        #expect(finished.description == .unchanged)
        #expect(finished.canCancel == .unchanged)
        #expect(finished.state == .set(.idle(stopReason: .endTurn, error: nil)))
    }

    @Test func incomingSessionMessageDecodes() throws {
        let notification = try Wire.params(SessionNotification.self, of: SubagentWire.incomingTask)
        guard case .sessionMessage(let message) = notification.update else {
            Issue.record("Expected a session message")
            return
        }
        // Sent on the child's own stream: the parent's task, as the child received it.
        #expect(notification.sessionId == SubagentWire.childID)
        #expect(message.messageId == SubagentWire.agentToolCallID)
        #expect(message.senderSessionId == SubagentWire.parentID)
        #expect(message.recipientSessionId == SubagentWire.childID)
        #expect(message.content == .set([.text("Reply with only the word: hi")]))
    }

    @Test(arguments: [
        (#"{"sessionId":"a7c82d0a6f0097318"}"#, Patch<String>.unchanged),
        (#"{"sessionId":"a7c82d0a6f0097318","title":null}"#, .cleared),
        (#"{"sessionId":"a7c82d0a6f0097318","title":"general-purpose"}"#, .set("general-purpose")),
    ])
    func titleIsAPatch(json: String, title: Patch<String>) throws {
        #expect(try Wire.decode(SubagentUpdate.self, from: json).title == title)
    }

    /// `capabilities` is replaced as a whole, and only a non-null `cancel` allows cancelling.
    @Test(arguments: [
        (#"{"sessionId":"a7c82d0a6f0097318"}"#, Patch<Bool>.unchanged),
        (#"{"sessionId":"a7c82d0a6f0097318","capabilities":null}"#, .set(false)),
        (#"{"sessionId":"a7c82d0a6f0097318","capabilities":{}}"#, .set(false)),
        (#"{"sessionId":"a7c82d0a6f0097318","capabilities":{"cancel":null}}"#, .set(false)),
        (#"{"sessionId":"a7c82d0a6f0097318","capabilities":{"cancel":{}}}"#, .set(true)),
    ])
    func cancelCapabilityIsReplacedWhole(json: String, canCancel: Patch<Bool>) throws {
        #expect(try Wire.decode(SubagentUpdate.self, from: json).canCancel == canCancel)
    }

    @Test(arguments: [
        (#"{"sessionId":"a7c82d0a6f0097318","state":null}"#, Patch<SubagentWorkState>.cleared),
        (#"{"sessionId":"a7c82d0a6f0097318","state":{"state":"requires_action"}}"#, .set(.requiresAction)),
        (
            #"{"sessionId":"a7c82d0a6f0097318","state":{"state":"idle","stopReason":"error","error":{"code":-32603,"message":"Internal error"}}}"#,
            .set(.idle(stopReason: .error, error: RPCError(code: -32603, message: "Internal error")))
        ),
        (#"{"sessionId":"a7c82d0a6f0097318","state":{"state":"unknown"}}"#, .set(.unknown)),
        (#"{"sessionId":"a7c82d0a6f0097318","state":{"state":"paused"}}"#, .set(.other("paused"))),
    ])
    func workStateDecodes(json: String, state: Patch<SubagentWorkState>) throws {
        #expect(try Wire.decode(SubagentUpdate.self, from: json).state == state)
    }

    // MARK: - Folding

    @Test func capturedRunFoldsIntoParentAndChildTranscripts() throws {
        var parent = SessionState()
        var child = SessionState()
        var workStates: [SubagentWorkState?] = []
        for line in SubagentWire.promptTurn {
            let notification = try Wire.params(SessionNotification.self, of: line)
            switch notification.sessionId {
            case SubagentWire.parentID:
                parent.apply(notification.update)
                if case .subagent = notification.update {
                    workStates.append(parent.subagents.first?.workState)
                }
            case SubagentWire.childID:
                child.apply(notification.update)
            default:
                Issue.record("Unexpected session \(notification.sessionId)")
            }
        }

        // One roster entry, patched in place between the tool call that started it and the reply.
        guard parent.items.count == 3,
            case .toolCall(let spawn) = parent.items[0],
            case .subagent(let subagent) = parent.items[1],
            case .message(let reply) = parent.items[2]
        else {
            Issue.record("Expected the Agent tool call, the subagent and a reply, got \(parent.items)")
            return
        }
        #expect(spawn.id == SubagentWire.agentToolCallID)
        #expect(spawn.status == .completed)
        #expect(subagent.id == SubagentWire.childID)
        #expect(subagent.title == "general-purpose")
        #expect(subagent.description == "Reply with hi")
        // The idle update omits capabilities, so cancelling stays allowed.
        #expect(subagent.canCancel)
        #expect(workStates == [.running, .idle(stopReason: .endTurn, error: nil)])
        #expect(reply.text == "done")

        guard child.items.count == 2,
            case .sessionMessage(let task) = child.items[0],
            case .message(let answer) = child.items[1]
        else {
            Issue.record("Expected the incoming task and the child's answer, got \(child.items)")
            return
        }
        #expect(task.id == SubagentWire.agentToolCallID)
        #expect(task.sender == SubagentWire.parentID)
        #expect(task.recipient == SubagentWire.childID)
        #expect(task.text == "Reply with only the word: hi")
        #expect(answer.role == .agent)
        #expect(answer.text == "hi")
    }

    @Test func rosterEntryKeepsItsPlaceAsItIsPatched() throws {
        var parent = SessionState()
        parent.apply(try Wire.update(SubagentWire.running))
        parent.apply(.agentMessageChunk(ContentChunk(content: .text("Waiting on it."), messageId: "m1")))
        parent.apply(
            .subagent(
                try Wire.decode(
                    SubagentUpdate.self,
                    from:
                        #"{"sessionId":"a7c82d0a6f0097318","title":null,"capabilities":null,"state":{"state":"requires_action"}}"#
                )))

        guard parent.items.count == 2, case .subagent(let subagent) = parent.items[0] else {
            Issue.record("Expected the subagent to stay first, got \(parent.items)")
            return
        }
        #expect(subagent.title == nil)
        #expect(subagent.description == "Reply with hi")
        #expect(!subagent.canCancel)
        #expect(subagent.workState == .requiresAction)
    }

    @Test func sessionMessageChunksAppendAndKeepParticipants() throws {
        var child = SessionState()
        // The RFD's streaming example: participants on the first chunk only.
        child.apply(
            try Wire.update(
                #"{"jsonrpc":"2.0","method":"session/update","params":{"sessionId":"a7c82d0a6f0097318","update":{"sessionUpdate":"session_message_chunk","messageId":"msg_2","senderSessionId":"b9e8f5f4-c297-4a0e-819f-9229a4f29594","recipientSessionId":"a7c82d0a6f0097318","content":{"type":"text","text":"Start by reproducing "}}}}"#
            ))
        child.apply(
            try Wire.update(
                #"{"jsonrpc":"2.0","method":"session/update","params":{"sessionId":"a7c82d0a6f0097318","update":{"sessionUpdate":"session_message_chunk","messageId":"msg_2","content":{"type":"text","text":"the bug."}}}}"#
            ))

        let message = try #require(sessionMessage(in: child))
        #expect(child.items.count == 1)
        #expect(message.sender == SubagentWire.parentID)
        #expect(message.recipient == SubagentWire.childID)
        #expect(message.text == "Start by reproducing the bug.")
    }

    @Test func sessionMessageContentIsAPatch() throws {
        var child = SessionState()
        child.apply(try Wire.update(SubagentWire.incomingTask))

        // A metadata-only upsert leaves the content alone.
        child.apply(
            try Wire.update(
                #"{"jsonrpc":"2.0","method":"session/update","params":{"sessionId":"a7c82d0a6f0097318","update":{"sessionUpdate":"session_message","messageId":"toolu_01S5Y6Qnqi9ei4VL8SjXndyP"}}}"#
            ))
        #expect(sessionMessage(in: child)?.text == "Reply with only the word: hi")

        child.apply(
            try Wire.update(
                #"{"jsonrpc":"2.0","method":"session/update","params":{"sessionId":"a7c82d0a6f0097318","update":{"sessionUpdate":"session_message","messageId":"toolu_01S5Y6Qnqi9ei4VL8SjXndyP","content":null}}}"#
            ))
        #expect(sessionMessage(in: child)?.content == [])
        // Participants are never cleared by omission.
        #expect(sessionMessage(in: child)?.sender == SubagentWire.parentID)
        #expect(child.items.count == 1)
    }

    /// Cursor sends the RFD's earlier draft: a spawn with a name and task, then plain-string states.
    @Test func cursorDraftSubagentMessagesFoldLikeTheRFD() throws {
        var parent = SessionState()
        parent.apply(
            try Wire.update(
                #"{"jsonrpc":"2.0","method":"session/update","params":{"sessionId":"parent-1","update":{"sessionUpdate":"subagent_spawned","subagentSessionId":"child-1","name":"explore","task":"Find the config loader","capabilities":{}}}}"#
            ))
        let spawned = try #require(parent.subagents.first)
        #expect(spawned.id == SessionID("child-1"))
        #expect(spawned.title == "explore")
        #expect(spawned.description == "Find the config loader")
        #expect(spawned.workState == .running)
        #expect(spawned.canCancel == false)

        for (state, expected) in [
            ("completed", SubagentWorkState.idle(stopReason: .endTurn, error: nil)),
            ("failed", .idle(stopReason: .error, error: nil)),
            ("cancelled", .idle(stopReason: .cancelled, error: nil)),
            ("disconnected", .unknown),
        ] {
            parent.apply(
                try Wire.update(
                    #"{"jsonrpc":"2.0","method":"session/update","params":{"sessionId":"parent-1","update":{"sessionUpdate":"subagent_state_update","subagentSessionId":"child-1","state":"\#(state)"}}}"#
                ))
            #expect(parent.subagents.first?.workState == expected)
            // A state change patches only the state.
            #expect(parent.subagents.first?.title == "explore")
        }
        #expect(parent.subagents.count == 1)
    }

}

private func sessionMessage(in state: SessionState) -> SessionMessage? {
    state.items.lazy.compactMap { item -> SessionMessage? in
        guard case .sessionMessage(let message) = item else { return nil }
        return message
    }.first
}

/// A captured run where the parent session launches one subagent through the Agent tool. Usage
/// updates, incremental tool input and the long hand-back `rawOutput` are left out.
enum SubagentWire {
    static let parentID = SessionID("b9e8f5f4-c297-4a0e-819f-9229a4f29594")
    static let childID = SessionID("a7c82d0a6f0097318")
    /// The child's incoming task reuses this as its message id.
    static let agentToolCallID = "toolu_01S5Y6Qnqi9ei4VL8SjXndyP"

    static let running =
        #"{"jsonrpc":"2.0","method":"session/update","params":{"sessionId":"b9e8f5f4-c297-4a0e-819f-9229a4f29594","update":{"sessionUpdate":"subagent_update","sessionId":"a7c82d0a6f0097318","title":"general-purpose","description":"Reply with hi","capabilities":{"cancel":{}},"state":{"state":"running"}}}}"#

    static let incomingTask =
        #"{"jsonrpc":"2.0","method":"session/update","params":{"sessionId":"a7c82d0a6f0097318","update":{"sessionUpdate":"session_message","messageId":"toolu_01S5Y6Qnqi9ei4VL8SjXndyP","senderSessionId":"b9e8f5f4-c297-4a0e-819f-9229a4f29594","recipientSessionId":"a7c82d0a6f0097318","content":[{"type":"text","text":"Reply with only the word: hi"}]}}}"#

    static let idle =
        #"{"jsonrpc":"2.0","method":"session/update","params":{"sessionId":"b9e8f5f4-c297-4a0e-819f-9229a4f29594","update":{"sessionUpdate":"subagent_update","sessionId":"a7c82d0a6f0097318","state":{"state":"idle","stopReason":"end_turn"}}}}"#

    static let promptTurn = [
        #"{"jsonrpc":"2.0","method":"session/update","params":{"sessionId":"b9e8f5f4-c297-4a0e-819f-9229a4f29594","update":{"_meta":{"claudeCode":{"toolName":"Agent"}},"toolCallId":"toolu_01S5Y6Qnqi9ei4VL8SjXndyP","sessionUpdate":"tool_call","name":"Agent","rawInput":{},"status":"pending","title":"Task","kind":"think","content":[]}}}"#,
        #"{"jsonrpc":"2.0","method":"session/update","params":{"sessionId":"b9e8f5f4-c297-4a0e-819f-9229a4f29594","update":{"_meta":{"claudeCode":{"toolName":"Agent"}},"toolCallId":"toolu_01S5Y6Qnqi9ei4VL8SjXndyP","sessionUpdate":"tool_call_update","rawInput":{"description":"Reply with hi"},"title":"Reply with hi"}}}"#,
        #"{"jsonrpc":"2.0","method":"session/update","params":{"sessionId":"b9e8f5f4-c297-4a0e-819f-9229a4f29594","update":{"_meta":{"claudeCode":{"toolName":"Agent"}},"toolCallId":"toolu_01S5Y6Qnqi9ei4VL8SjXndyP","sessionUpdate":"tool_call_update","rawInput":{"description":"Reply with hi","subagent_type":"general-purpose","prompt":"Reply with only the word: hi","run_in_background":false},"content":[{"type":"content","content":{"type":"text","text":"Reply with only the word: hi"}}]}}}"#,
        running,
        incomingTask,
        #"{"jsonrpc":"2.0","method":"session/update","params":{"sessionId":"a7c82d0a6f0097318","update":{"sessionUpdate":"agent_message_chunk","content":{"type":"text","text":"hi"},"_meta":{"claudeCode":{"parentToolUseId":"toolu_01S5Y6Qnqi9ei4VL8SjXndyP"}},"messageId":"msg_011Cg7dqcvPZfJxJmrN9UY4M"}}}"#,
        idle,
        #"{"jsonrpc":"2.0","method":"session/update","params":{"sessionId":"b9e8f5f4-c297-4a0e-819f-9229a4f29594","update":{"_meta":{"claudeCode":{"toolName":"Agent"}},"toolCallId":"toolu_01S5Y6Qnqi9ei4VL8SjXndyP","sessionUpdate":"tool_call_update","status":"completed","content":[{"type":"content","content":{"type":"text","text":"hi"}}]}}}"#,
        #"{"jsonrpc":"2.0","method":"session/update","params":{"sessionId":"b9e8f5f4-c297-4a0e-819f-9229a4f29594","update":{"sessionUpdate":"agent_message_chunk","content":{"type":"text","text":"done"},"messageId":"msg_011Cg7dqoDkzDraZGyBjM1wd"}}}"#,
    ]
}
