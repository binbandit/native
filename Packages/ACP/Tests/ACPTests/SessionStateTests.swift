import Foundation
import Testing

@testable import ACP

struct SessionStateTests {
    @Test func capturedTurnFoldsIntoATranscript() throws {
        var state = SessionState()
        state.appendUserMessage(Wire.promptText)
        for line in Wire.promptTurn {
            switch try Wire.event(line) {
            case .sessionUpdate(let notification):
                state.apply(notification.update)
            case .permissionRequest(let id, let request):
                state.requestPermission(request, id: id)
                #expect(state.pendingPermissions.map { $0.toolCallID } == [Wire.writeToolCallID])
                // The client allowed it straight away, as in the capture.
                state.resolvePermission(toolCallID: request.toolCall.toolCallId)
            case .elicitationRequest:
                Issue.record("Unexpected question")
            case .disconnected:
                Issue.record("Unexpected disconnect")
            }
        }
        state.endTurn(try Wire.decode(PromptResponse.self, from: Wire.promptResult).stopReason)

        guard state.items.count == 5,
            case .message(let prompt) = state.items[0],
            case .toolCall(let read) = state.items[1],
            case .toolCall(let write) = state.items[2],
            case .toolCall(let bash) = state.items[3],
            case .message(let reply) = state.items[4]
        else {
            Issue.record("Expected prompt, three tool calls and a reply, got \(state.items)")
            return
        }
        #expect(prompt.role == .user)

        let calls = [read, write, bash]
        #expect(calls.map(\.id) == [Wire.readToolCallID, Wire.writeToolCallID, Wire.bashToolCallID])
        #expect(
            calls.map(\.title) == [
                "Read /private/tmp/acp-research/sandbox/notes.txt", "Write /private/tmp/acp-research/sandbox/out.txt",
                "ls",
            ])
        #expect(calls.map(\.kind) == [.read, .edit, .execute])
        #expect(calls.map(\.status) == [.completed, .completed, .completed])
        #expect(calls.allSatisfy { $0.permission == nil })
        // Write's completing update omits content, so the diff survives it.
        #expect(
            write.content == [
                .diff(FileDiff(path: "/private/tmp/acp-research/sandbox/out.txt", oldText: nil, newText: "done\n"))
            ])
        #expect(bash.content == [.content(.text("```console\nnotes.txt\nout.txt\n```"))])

        #expect(reply.role == .agent)
        #expect(reply.messageID == Wire.agentMessageID)
        #expect(reply.text == Wire.agentMessage)

        #expect(state.usage?.used == 234_506)
        #expect(state.usage?.cost?.amount == 0.19107000000000002)
    }

    // MARK: - Message chunks

    @Test func chunksSharingAMessageIDMerge() {
        let state = folded([agentChunk("Hel", id: "m1"), agentChunk("lo", id: "m1")])
        #expect(state.messages.map(\.text) == ["Hello"])
    }

    @Test func aNewMessageIDStartsANewMessage() {
        let state = folded([agentChunk("One.", id: "m1"), agentChunk("Two.", id: "m2")])
        #expect(state.messages.map(\.text) == ["One.", "Two."])
        #expect(state.messages.map(\.messageID) == ["m1", "m2"])
    }

    @Test func chunksWithoutAMessageIDContinueTheLastMessage() {
        let state = folded([agentChunk("Hel", id: "m1"), agentChunk("lo", id: nil)])
        #expect(state.messages.map(\.text) == ["Hello"])
    }

    @Test func aRoleChangeStartsANewMessage() {
        var state = SessionState()
        state.appendUserMessage("Hi")
        state.apply(.agentThoughtChunk(ContentChunk(content: .text("Thinking"), messageId: "m1")))
        state.apply(agentChunk("Hello", id: "m1"))
        #expect(state.messages.map(\.role) == [.user, .thought, .agent])
        #expect(state.messages.map(\.text) == ["Hi", "Thinking", "Hello"])
    }

    @Test func aToolCallBetweenChunksSplitsTheMessage() throws {
        let state = folded([
            agentChunk("Checking.", id: "m1"), try Wire.update(Wire.readToolCall), agentChunk("Done.", id: "m1"),
        ])
        #expect(state.items.count == 3)
        #expect(state.messages.map(\.text) == ["Checking.", "Done."])
    }

    // MARK: - Permissions and turn endings

    @Test func permissionRequestAttachesToItsToolCallUntilResolved() throws {
        var state = folded([try Wire.update(Wire.writeToolCall)])
        let request = try Wire.params(RequestPermissionRequest.self, of: Wire.permissionRequest)

        state.requestPermission(request, id: .int(0))
        let waiting = try #require(state.toolCall(Wire.writeToolCallID))
        // The request's newer details replace the placeholder title.
        #expect(waiting.title == "Write /private/tmp/acp-research/sandbox/out.txt")
        #expect(waiting.permission == PendingPermission(requestID: .int(0), options: request.options))
        #expect(state.pendingPermissions.map { $0.toolCallID } == [Wire.writeToolCallID])

        let resolved = state.resolvePermission(toolCallID: Wire.writeToolCallID)
        #expect(resolved?.requestID == .int(0))
        #expect(state.toolCall(Wire.writeToolCallID)?.permission == nil)
        #expect(state.pendingPermissions.isEmpty)
    }

    @Test func cancelledTurnClosesOpenToolCalls() throws {
        var state = folded(
            try [Wire.readToolCall, Wire.readCompletedUpdate, Wire.writeToolCall, Wire.bashToolCall].map(Wire.update))
        state.requestPermission(try Wire.params(RequestPermissionRequest.self, of: Wire.permissionRequest), id: .int(0))

        state.endTurn(.cancelled)

        #expect(state.toolCall(Wire.readToolCallID)?.status == .completed)
        #expect(state.toolCall(Wire.writeToolCallID)?.status == .cancelled)
        #expect(state.toolCall(Wire.bashToolCallID)?.status == .cancelled)
        #expect(state.pendingPermissions.isEmpty)
        #expect(state.notices.map(\.isError) == [false])
        guard case .notice = state.items.last else {
            Issue.record("Expected the turn to end with a notice")
            return
        }
    }

    @Test(arguments: [StopReason.maxTokens, .maxTurnRequests, .refusal, .other("server_error")])
    func abnormalStopsAddAnErrorNotice(_ stopReason: StopReason) {
        var state = folded([agentChunk("Partial", id: "m1")])
        state.endTurn(stopReason)
        #expect(state.notices.map(\.isError) == [true])
    }

    /// A failed prompt is explained by whoever saw the error, so ending the turn only stops its clock.
    @Test func failedTurnsEndWithoutAGenericNotice() throws {
        var state = folded([agentChunk("Partial", id: "m1")])
        state.appendUserMessage("Go")
        state.endTurn(.error)
        #expect(state.notices.isEmpty)
        let clock = try #require(state.turnClocks.values.first { $0.stopReason == .error })
        #expect(clock.endedAt != nil)
    }

    @Test func usageKeepsTheLastKnownCost() throws {
        let state = folded(try [Wire.usageWithCost, Wire.usageWithoutCost].map(Wire.update))
        #expect(state.usage?.used == 234_117)
        #expect(state.usage?.cost == Usage.Cost(amount: 0.19107000000000002, currency: "USD"))
    }
}

private func folded(_ updates: [SessionUpdate]) -> SessionState {
    var state = SessionState()
    for update in updates {
        state.apply(update)
    }
    return state
}

private func agentChunk(_ text: String, id: String?) -> SessionUpdate {
    .agentMessageChunk(ContentChunk(content: .text(text), messageId: id))
}

private extension SessionState {
    var messages: [TranscriptMessage] {
        items.compactMap { item -> TranscriptMessage? in
            guard case .message(let message) = item else { return nil }
            return message
        }
    }

    var notices: [TranscriptNotice] {
        items.compactMap { item -> TranscriptNotice? in
            guard case .notice(let notice) = item else { return nil }
            return notice
        }
    }

    func toolCall(_ id: String) -> ToolCallState? {
        items.lazy.compactMap { item -> ToolCallState? in
            guard case .toolCall(let call) = item, call.id == id else { return nil }
            return call
        }.first
    }
}
