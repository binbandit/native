import Foundation
import Testing

@testable import ACP

/// codex-acp 2.2.2 with `gpt-6.1-sol`, a client declaring no terminals, running
/// `for i in $(seq 1 30); do echo tick $i; sleep 1; done` (captured 2026-10-20). Stopped: the agent
/// answers `cancelled` at once, and the command keeps printing after it. Cut off by the agent's stdin
/// closing (what a host crash does): nothing more arrives, and a reload replays the command as failed
/// with exit code -1.
private enum CodexCutOffWire {
    static let stoppedID = "exec-ceac78a5-8ba2-4b29-a472-05a2f70c8b36"
    static let stoppedRun = [
        #"{"jsonrpc":"2.0","method":"session/update","params":{"sessionId":"01a158ad-6cdf-7902-bbea-348f3b93bd15","update":{"sessionUpdate":"tool_call","toolCallId":"exec-ceac78a5-8ba2-4b29-a472-05a2f70c8b36","name":"exec_command","kind":"execute","title":"for i in $(seq 1 30); do echo tick $i; sleep 1; done","status":"in_progress","content":[{"type":"terminal","terminalId":"exec-ceac78a5-8ba2-4b29-a472-05a2f70c8b36"}],"rawInput":{"command":"for i in $(seq 1 30); do echo tick $i; sleep 1; done","cwd":"/tmp/turn-life/work"},"_meta":{"terminal_info":{"cwd":"/tmp/turn-life/work","terminal_id":"exec-ceac78a5-8ba2-4b29-a472-05a2f70c8b36"}}}}}"#,
        #"{"jsonrpc":"2.0","method":"session/update","params":{"sessionId":"01a158ad-6cdf-7902-bbea-348f3b93bd15","update":{"sessionUpdate":"tool_call_update","toolCallId":"exec-ceac78a5-8ba2-4b29-a472-05a2f70c8b36","_meta":{"terminal_output_delta":{"data":"tick 2\n","terminal_id":"exec-ceac78a5-8ba2-4b29-a472-05a2f70c8b36"}}}}}"#,
    ]
    /// After the agent answered `cancelled`.
    static let afterStop = [
        #"{"jsonrpc":"2.0","method":"session/update","params":{"sessionId":"01a158ad-6cdf-7902-bbea-348f3b93bd15","update":{"sessionUpdate":"tool_call_update","toolCallId":"exec-ceac78a5-8ba2-4b29-a472-05a2f70c8b36","_meta":{"terminal_output_delta":{"data":"tick 4\n","terminal_id":"exec-ceac78a5-8ba2-4b29-a472-05a2f70c8b36"}}}}}"#
    ]

    static let cutOffID = "exec-96e0af4d-4547-43f1-9d87-034a4950f85c"
    static let cutOffRun = [
        #"{"jsonrpc":"2.0","method":"session/update","params":{"sessionId":"01a158ad-a414-7140-8dbc-83fff80e8824","update":{"sessionUpdate":"tool_call","toolCallId":"exec-96e0af4d-4547-43f1-9d87-034a4950f85c","name":"exec_command","kind":"execute","title":"for i in $(seq 1 30); do echo tick $i; sleep 1; done","status":"in_progress","content":[{"type":"terminal","terminalId":"exec-96e0af4d-4547-43f1-9d87-034a4950f85c"}],"rawInput":{"command":"for i in $(seq 1 30); do echo tick $i; sleep 1; done","cwd":"/tmp/turn-life/work"},"_meta":{"terminal_info":{"cwd":"/tmp/turn-life/work","terminal_id":"exec-96e0af4d-4547-43f1-9d87-034a4950f85c"}}}}}"#,
        #"{"jsonrpc":"2.0","method":"session/update","params":{"sessionId":"01a158ad-a414-7140-8dbc-83fff80e8824","update":{"sessionUpdate":"tool_call_update","toolCallId":"exec-96e0af4d-4547-43f1-9d87-034a4950f85c","_meta":{"terminal_output_delta":{"data":"tick 2\n","terminal_id":"exec-96e0af4d-4547-43f1-9d87-034a4950f85c"}}}}}"#,
    ]
    static let cutOffReplay = [
        #"{"jsonrpc":"2.0","method":"session/update","params":{"sessionId":"01a158ad-a414-7140-8dbc-83fff80e8824","update":{"sessionUpdate":"user_message_chunk","messageId":"01a158ad-ace6-7313-acde-c3d1fcbeb00e","content":{"type":"text","text":"Run this exact shell command and wait for it to finish: for i in $(seq 1 30); do echo tick $i; sleep 1; done. Then reply with only the last line it printed. Don't change any files."}}}}"#,
        #"{"jsonrpc":"2.0","method":"session/update","params":{"sessionId":"01a158ad-a414-7140-8dbc-83fff80e8824","update":{"sessionUpdate":"agent_message_chunk","messageId":"msg_0d62a05f1e8619d1016ad736b5ba808191848a85463b7a97be","content":{"type":"text","text":"I’ll run the command and wait for it to finish.\n"}}}}"#,
        #"{"jsonrpc":"2.0","method":"session/update","params":{"sessionId":"01a158ad-a414-7140-8dbc-83fff80e8824","update":{"sessionUpdate":"tool_call","toolCallId":"exec-96e0af4d-4547-43f1-9d87-034a4950f85c","name":"exec_command","kind":"execute","title":"for i in $(seq 1 30); do echo tick $i; sleep 1; done","status":"failed","content":[{"type":"terminal","terminalId":"exec-96e0af4d-4547-43f1-9d87-034a4950f85c"}],"rawInput":{"command":"for i in $(seq 1 30); do echo tick $i; sleep 1; done","cwd":"/tmp/turn-life/work"},"_meta":{"terminal_info":{"cwd":"/tmp/turn-life/work","terminal_id":"exec-96e0af4d-4547-43f1-9d87-034a4950f85c"}}}}}"#,
        #"{"jsonrpc":"2.0","method":"session/update","params":{"sessionId":"01a158ad-a414-7140-8dbc-83fff80e8824","update":{"sessionUpdate":"tool_call_update","toolCallId":"exec-96e0af4d-4547-43f1-9d87-034a4950f85c","_meta":{"terminal_output_delta":{"data":"tick 1\ntick 2\ntick 3\n","terminal_id":"exec-96e0af4d-4547-43f1-9d87-034a4950f85c"},"terminal_exit":{"exit_code":-1,"signal":null,"terminal_id":"exec-96e0af4d-4547-43f1-9d87-034a4950f85c"}}}}}"#,
    ]
}

private let start = Date(timeIntervalSinceReferenceDate: 0)

private func at(_ seconds: TimeInterval) -> Date {
    start.addingTimeInterval(seconds)
}

private func applying(_ lines: [String], to state: inout SessionState, at date: Date = start) throws {
    for line in lines {
        state.apply(try Wire.update(line), at: date)
    }
}

private func reply(_ text: String) -> SessionUpdate {
    .agentMessageChunk(ContentChunk(content: .text(text)))
}

@Suite("Turn endings settle what the turn left open")
struct TurnEndingTests {
    @Test("A forced stop closes open tools and shows one agent-specific receipt")
    func forcedStopReceipt() throws {
        var state = SessionState()
        state.appendUserMessage("Run it", at: start)
        try applying(CodexCutOffWire.cutOffRun, to: &state, at: at(1))
        state.endTurn(.cancelled, at: at(4), stoppedMessage: "Stopped. Example didn't respond, so Native stopped it.")
        #expect(state.call(CodexCutOffWire.cutOffID)?.status == .cancelled)
        #expect(state.call(CodexCutOffWire.cutOffID)?.finishedAt == at(4))
        #expect(state.notices.map(\.text) == ["Stopped. Example didn't respond, so Native stopped it."])
        #expect(state.turns.last?.stopReason == .cancelled)
    }

    @Test("A call the agent never closed reads as unreported once the turn ends, its clock stopped there")
    func normalEndSettlesOpenCalls() throws {
        var state = SessionState()
        state.appendUserMessage("permission", at: start)
        // The approval names the call, and nothing after it says how the call went.
        state.requestPermission(
            try Wire.params(RequestPermissionRequest.self, of: Wire.permissionRequest), id: .int(0), at: at(1))
        state.resolvePermission(toolCallID: Wire.writeToolCallID)
        state.apply(reply("Done."), at: at(30))
        state.endTurn(.endTurn, at: at(36))

        let call = try #require(state.call(Wire.writeToolCallID))
        #expect(call.status == .unreported)
        #expect(call.finishedAt == at(36))
        #expect(state.notices.isEmpty)
        // It claims no edit, so the turn changed nothing it can vouch for.
        #expect(state.summary(of: try #require(state.turns.last)).changedFiles.isEmpty)
    }

    @Test("What the agent reports later still lands, but nothing runs again once its turn is over")
    func settledCallsTakeLateOutcomesOnly() throws {
        var state = SessionState()
        state.appendUserMessage("Go", at: start)
        try applying([Wire.writeToolCall], to: &state, at: at(1))
        state.endTurn(.endTurn, at: at(2))

        state.apply(.toolCallUpdate(ToolCallUpdate(toolCallId: Wire.writeToolCallID, status: .inProgress)))
        #expect(state.call(Wire.writeToolCallID)?.status == .unreported)
        state.apply(.toolCallUpdate(ToolCallUpdate(toolCallId: Wire.writeToolCallID, status: .completed)))
        #expect(state.call(Wire.writeToolCallID)?.status == .completed)
    }

    @Test("A stopped call stays stopped when the agent reports it failed afterwards")
    func failureAfterAStopIsTheStops() throws {
        var state = SessionState()
        state.appendUserMessage("Go", at: start)
        try applying([Wire.bashToolCall], to: &state)
        state.endTurn(.cancelled)
        state.apply(.toolCallUpdate(ToolCallUpdate(toolCallId: Wire.bashToolCallID, status: .failed)))
        #expect(state.call(Wire.bashToolCallID)?.status == .cancelled)
    }

    @Test("Codex's stopped command reads stopped, and its output after the stop stays with it")
    func codexStopKeepsTheCommandsOutput() throws {
        var state = SessionState()
        state.appendUserMessage("Run it", at: start)
        try applying(CodexCutOffWire.stoppedRun, to: &state, at: at(1))
        state.endTurn(.cancelled, at: at(3))
        try applying(CodexCutOffWire.afterStop, to: &state, at: at(4))

        let call = try #require(state.call(CodexCutOffWire.stoppedID))
        #expect(call.status == .cancelled)
        #expect(call.finishedAt == at(3))
        #expect(call.terminalOutput == "tick 2\ntick 4\n")
        // Updates to the stopped turn's own call aren't new output, so the turn stays whole.
        #expect(state.turns.count == 1)
    }

    @Test("A command cut off by the agent going away replays as interrupted, not as exit -1")
    func codexReplayOfACutOffCommandIsInterrupted() throws {
        var state = SessionState()
        try applying(CodexCutOffWire.cutOffReplay, to: &state)
        #expect(state.call(CodexCutOffWire.cutOffID)?.status == .failed)
        state.endReplay()

        let call = try #require(state.call(CodexCutOffWire.cutOffID))
        #expect(call.status == .interrupted)
        #expect(call.terminalOutput == "tick 1\ntick 2\ntick 3\n")
        #expect(call.exitCode == -1)
    }

    @Test("A command that died mid-turn, with the agent carrying on, is the command's own failure")
    func killedCommandTheAgentMovedOnFromStaysFailed() throws {
        var state = SessionState()
        try applying(CodexCutOffWire.cutOffReplay, to: &state)
        state.apply(reply("It was killed; trying another way."))
        state.endReplay()
        #expect(state.call(CodexCutOffWire.cutOffID)?.status == .failed)
    }

    @Test("Calls history left open are over once the replay ends")
    func replayedOpenCallsAreUnreported() throws {
        var state = SessionState()
        try applying(Array(CodexCutOffWire.cutOffRun.prefix(1)), to: &state)
        state.apply(reply("Next."))
        state.appendUserMessage("Then?")
        state.endReplay()
        #expect(state.call(CodexCutOffWire.cutOffID)?.status == .unreported)
    }

    @Test("A recovery interrupts what the cut-off turn left running, at the time it was cut off")
    func recoveryInterruptsTheOpenTurn() throws {
        var state = SessionState()
        state.appendUserMessage("Run it", at: start)
        try applying(CodexCutOffWire.cutOffRun, to: &state, at: at(10))
        state.interruptTurn(at: at(4))

        let call = try #require(state.call(CodexCutOffWire.cutOffID))
        #expect(call.status == .interrupted)
        // The host dates a crash by its last heartbeat, which can come before the call started.
        #expect(call.finishedAt == at(10))
        #expect(state.turns.last?.endedAt == nil)
    }

    @Test("After a reload, recovery turns what the replay left unreported into interrupted")
    func recoveryAfterReplay() throws {
        var state = SessionState()
        try applying([CodexCutOffWire.cutOffReplay[0]] + Array(CodexCutOffWire.cutOffRun.prefix(1)), to: &state)
        state.endReplay()
        #expect(state.call(CodexCutOffWire.cutOffID)?.status == .unreported)
        state.interruptTurn(at: start)
        #expect(state.call(CodexCutOffWire.cutOffID)?.status == .interrupted)
    }
}

@Suite("Output after a stop")
struct LateOutputTests {
    @Test("What the agent sends after a stop is a turn of its own, opened by a notice")
    func lateOutputIsItsOwnTurn() throws {
        var state = SessionState()
        state.appendUserMessage("stubborn 60", at: start)
        state.apply(reply("tick 1\n"), at: at(1))
        state.endTurn(.cancelled, at: at(2))
        state.appendNotice("Fake Agent didn't confirm it stopped, so Native stopped waiting.", isError: false)
        state.apply(reply("tick 43\n"))
        state.apply(reply("tick 44\n"))

        let turns = state.turns
        #expect(turns.count == 2)
        #expect(turns.map(\.isLateOutput) == [false, true])
        #expect(turns[0].stopReason == .cancelled)
        #expect(turns[0].endedAt == at(2))
        guard case .notice(let notice) = state.items[turns[1].items.lowerBound],
            case .message(let late) = state.items[turns[1].items.lowerBound + 1]
        else {
            Issue.record("Expected the late turn to open with its notice, then the output")
            return
        }
        #expect(notice.text == "The agent kept going after the stop.")
        #expect(!notice.isError)
        #expect(late.text == "tick 43\ntick 44\n")
        // The stopped turn still ends with the notice that explains it.
        guard case .notice(let ending) = state.items[turns[0].items.upperBound - 1] else {
            Issue.record("Expected the stopped turn to end with its notice")
            return
        }
        #expect(ending.text.hasPrefix("Fake Agent didn't confirm"))
    }

    @Test("The next prompt starts an ordinary turn again")
    func nextPromptIsOrdinary() {
        var state = SessionState()
        state.appendUserMessage("stubborn 60")
        state.endTurn(.cancelled)
        state.apply(reply("tick 43\n"))
        state.appendUserMessage("hello")
        state.apply(reply("echo: hello"))
        state.endTurn(.endTurn)
        #expect(state.turns.map(\.isLateOutput) == [false, true, false])
        #expect(state.notices.map(\.text) == ["Stopped.", "The agent kept going after the stop."])
    }

    @Test("Nothing after a normal end counts as late")
    func normalEndHasNoLateOutput() {
        var state = SessionState()
        state.appendUserMessage("hi")
        state.endTurn(.endTurn)
        state.apply(reply("trailing"))
        #expect(state.turns.count == 1)
    }
}

@Suite("A message Native sends again")
struct DeliveryRetryTests {
    private let retry = DeliveryRetry(
        agentName: "Fake Agent", reason: "Network error: connection reset by peer", delay: 5)

    @Test("The notice follows the retry from the promise to its outcome, in one place")
    func retryThatWentThrough() throws {
        var state = SessionState()
        state.appendUserMessage("flaky-once hello", at: start)
        state.failTurn("ignored when retrying", retry: retry, at: at(1))

        let waiting = try #require(state.notices.first)
        #expect(
            waiting.text
                == "Fake Agent couldn't be reached (Network error: connection reset by peer). Native kept your message and will try again in 5 seconds. Use Stop to cancel."
        )
        #expect(waiting.isError)
        // Waiting isn't an ending: the turn has no footer to pull the notice into.
        #expect(state.turns.last?.endedAt == nil)
        #expect(state.turns.last?.stopReason == nil)

        let retried = state.retryTurn()
        #expect(retried)
        #expect(state.notices.first?.retry?.progress == .retrying)
        #expect(state.notices.first?.isError == false)
        state.apply(reply("echo: flaky-once hello"), at: at(7))
        state.endTurn(.endTurn, at: at(7))

        let settled = try #require(state.notices.first)
        #expect(settled.id == waiting.id)
        #expect(settled.text == "Reconnected to Fake Agent, and your message went through on retry.")
        #expect(!settled.isError)
        #expect(state.notices.count == 1)
        let turn = try #require(state.turns.last)
        #expect(state.turns.count == 1)
        #expect(turn.duration == 7)
        #expect(turn.stopReason == .endTurn)
    }

    @Test("Trying again and failing again keeps one notice, which ends as the final failure")
    func retriesThatKeepFailing() throws {
        var state = SessionState()
        state.appendUserMessage("flaky", at: start)
        state.failTurn("", retry: retry, at: at(1))
        state.retryTurn()
        state.failTurn("", retry: DeliveryRetry(agentName: "Fake Agent", reason: "timed out", delay: 20), at: at(7))
        #expect(state.notices.count == 1)
        #expect(state.notices.first?.text.contains("will try again in 20 seconds") == true)

        state.retryTurn()
        state.failTurn("Network error: timed out", at: at(30))
        #expect(state.notices.map(\.text) == ["Network error: timed out"])
        #expect(state.notices.first?.isError == true)
        #expect(state.turns.last?.stopReason == .error)
        #expect(state.turns.last?.endedAt == at(30))
    }

    @Test("A retry that got somewhere went through, whatever fails after it")
    func retryThatMadeProgressThenFailed() {
        var state = SessionState()
        state.appendUserMessage("flaky", at: start)
        state.failTurn("", retry: retry, at: at(1))
        state.retryTurn()
        state.apply(reply("Working on it"), at: at(8))
        state.failTurn("Internal error", at: at(9))
        #expect(
            state.notices.map(\.text) == [
                "Reconnected to Fake Agent, and your message went through on retry.", "Internal error",
            ])
    }

    @Test("Stopping the wait settles the notice in the past, and the turn ended when it failed")
    func stoppingTheWait() throws {
        var state = SessionState()
        state.appendUserMessage("flaky", at: start)
        state.failTurn("", retry: retry, at: at(1))
        state.stopRetrying(at: at(4))

        let notice = try #require(state.notices.first)
        #expect(notice.text == "Fake Agent couldn't be reached (Network error: connection reset by peer).")
        #expect(notice.isError)
        #expect(state.turns.last?.stopReason == .error)
        #expect(state.turns.last?.endedAt == at(1))
        let retried = state.retryTurn()
        #expect(!retried)
    }

    @Test("A new message ends the wait")
    func newMessageEndsTheWait() {
        var state = SessionState()
        state.appendUserMessage("flaky", at: start)
        state.failTurn("", retry: retry, at: at(1))
        state.appendUserMessage("never mind", at: at(2))
        #expect(state.notices.first?.retry?.progress == .gaveUp)
        #expect(state.turns.first?.stopReason == .error)
        #expect(state.turns.last?.isOpen == true)
    }

    @Test("A message waiting to go out again hasn't delivered its instructions")
    func waitingDoesntDeliverThePreamble() {
        var state = SessionState()
        let marker = PromptPreamble.Marker(id: "plan", label: "Plan")
        state.appendUserMessage("flaky", preamble: marker, at: start)
        state.failTurn("", retry: retry, at: at(1))
        #expect(state.deliveredPreamble == nil)
        state.retryTurn()
        #expect(state.deliveredPreamble == marker)
    }
}

private extension SessionState {
    func call(_ id: String) -> ToolCallState? {
        items.lazy.compactMap { item -> ToolCallState? in
            guard case .toolCall(let call) = item, call.id == id else { return nil }
            return call
        }.first
    }

    var notices: [TranscriptNotice] {
        items.compactMap { item -> TranscriptNotice? in
            guard case .notice(let notice) = item else { return nil }
            return notice
        }
    }
}
