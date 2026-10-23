import ACP
import Foundation
import NativeHostProtocol
import Testing

@Suite("Session mirror")
struct SessionMirrorTests {
    private func chunk(_ kind: String, _ text: String, id: String? = nil) -> HostEvent.Payload {
        var update: [String: JSONValue] = [
            "sessionUpdate": .string(kind), "content": .object(["type": .string("text"), "text": .string(text)]),
        ]
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
        mirror.apply([
            HostEvent(seq: 1, payload: .reset(loading: true)),
            HostEvent(seq: 2, payload: chunk("user_message_chunk", "Replayed", id: "m0")),
        ])
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
            "options": .array([
                .object(["optionId": .string("allow"), "name": .string("Allow"), "kind": .string("allow_once")])
            ]),
        ])
        var mirror = SessionMirror()
        let requestedAt = Date(timeIntervalSince1970: 1_000)
        mirror.apply(
            HostEvent(seq: 1, at: requestedAt, payload: .permissionRequested(toolCallID: "call-1", request: request)))
        #expect(mirror.state.pendingPermissions.first?.permission.requestedAt == requestedAt)
        #expect(mirror.state.pendingPermissions.map(\.toolCallID) == ["call-1"])
        mirror.apply(HostEvent(seq: 2, payload: .permissionResolved(toolCallID: "call-1", optionID: "allow")))
        #expect(mirror.state.pendingPermissions.isEmpty)
    }

    @Test("Question clocks use the host event time when a client attaches later")
    func questionArrival() {
        let requestedAt = Date(timeIntervalSince1970: 1_000)
        let request = JSONValue.object([
            "sessionId": .string("s"), "mode": .string("form"),
            "message": .string("Which template?"),
            "requestedSchema": .object(["type": .string("object"), "properties": .object([:])]),
        ])
        var mirror = SessionMirror()
        mirror.apply(
            HostEvent(seq: 1, at: requestedAt, payload: .questionAsked(questionID: "question", request: request)))
        #expect(mirror.questions.first?.requestedAt == requestedAt)
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

/// What a session's events leave the transcript saying once a turn ends or is cut off, on every
/// client that folds them.
@Suite("Session mirror: turn endings")
struct SessionMirrorTurnEndingTests {
    private let agent = "Fake Agent"
    private let start = Date(timeIntervalSince1970: 1_800_000_000)

    private func at(_ seconds: TimeInterval) -> Date {
        start.addingTimeInterval(seconds)
    }

    private func chunk(_ text: String) -> HostEvent.Payload {
        .update(
            .object([
                "sessionUpdate": .string("agent_message_chunk"),
                "content": .object(["type": .string("text"), "text": .string(text)]),
            ]))
    }

    private func decoded(_ line: String) throws -> HostEvent.Payload {
        let message = try JSONDecoder().decode(JSONValue.self, from: Data(line.utf8))
        return .update(try #require(message["params"]?["update"]))
    }

    private func mirror(_ payloads: [(TimeInterval, HostEvent.Payload)]) -> SessionMirror {
        var mirror = SessionMirror()
        for (seq, (seconds, payload)) in payloads.enumerated() {
            mirror.apply(HostEvent(seq: seq + 1, at: at(seconds), payload: payload))
        }
        return mirror
    }

    private func notices(_ mirror: SessionMirror) -> [TranscriptNotice] {
        mirror.state.items.compactMap { item in
            if case .notice(let notice) = item { notice } else { nil }
        }
    }

    private func calls(_ mirror: SessionMirror) -> [ToolCallState] {
        mirror.state.items.compactMap { item in
            if case .toolCall(let call) = item { call } else { nil }
        }
    }

    @Test("A call the agent never closed stops running when the turn ends, without claiming success")
    func unclosedCallIsUnreported() throws {
        let request = JSONValue.object([
            "sessionId": .string("s"),
            "toolCall": .object([
                "toolCallId": .string("call-1"), "title": .string("Write notes.txt"), "kind": .string("edit"),
            ]),
            "options": .array([
                .object(["optionId": .string("allow"), "name": .string("Allow"), "kind": .string("allow_once")])
            ]),
        ])
        let mirror = mirror([
            (0, .reset(loading: false)),
            (0, .prompt(PromptEcho(text: "permission", requestID: UUID()))),
            (1, .permissionRequested(toolCallID: "call-1", request: request)),
            (5, .permissionResolved(toolCallID: "call-1", optionID: "allow")),
            (6, chunk("permission: allow")),
            (6, .turnEnded(stopReason: "end_turn")),
        ])
        let call = try #require(calls(mirror).first)
        #expect(call.status == .unreported)
        #expect(call.startedAt == at(1))
        #expect(call.finishedAt == at(6))
    }

    @Test("A passing failure's notice follows the retry through, in the same place")
    func retryThatWentThrough() throws {
        let id = UUID()
        let retry = DeliveryRetry(agentName: agent, reason: "Network error: connection reset by peer", delay: 5)
        var mirror = mirror([
            (0, .reset(loading: false)),
            (0, .prompt(PromptEcho(text: "flaky-once hello", requestID: id))),
            (0.1, .turnFailed(message: retry.waitingText, error: nil, retry: retry)),
        ])
        let waiting = try #require(notices(mirror).first)
        #expect(waiting.isError)
        #expect(waiting.text.hasSuffix("will try again in 5 seconds. Use Stop to cancel."))
        // A turn waiting for its retry hasn't ended, so its notice isn't the turn's ending.
        #expect(mirror.state.turns.last?.stopReason == nil)

        mirror.apply(
            HostEvent(
                seq: 4, at: at(5),
                payload: .prompt(PromptEcho(text: "flaky-once hello", origin: .queued, requestID: id, shown: false))))
        mirror.apply(HostEvent(seq: 5, at: at(5.2), payload: chunk("echo: flaky-once hello")))
        mirror.apply(HostEvent(seq: 6, at: at(5.2), payload: .turnEnded(stopReason: "end_turn")))

        #expect(notices(mirror).map(\.text) == ["Reconnected to Fake Agent, and your message went through on retry."])
        #expect(notices(mirror).first?.isError == false)
        #expect(notices(mirror).first?.id == waiting.id)
        #expect(mirror.userMessages == ["flaky-once hello"])
        let turn = try #require(mirror.state.turns.last)
        #expect(mirror.state.turns.count == 1)
        #expect(turn.stopReason == .endTurn)
        #expect(abs((turn.duration ?? 0) - 5.2) < 0.001)
    }

    @Test("Stopping the retry leaves the failure in the past tense")
    func stoppedRetry() throws {
        let retry = DeliveryRetry(agentName: agent, reason: "Network error", delay: 5)
        let mirror = mirror([
            (0, .reset(loading: false)),
            (0, .prompt(PromptEcho(text: "flaky-once hello", requestID: UUID()))),
            (0.1, .turnFailed(message: retry.waitingText, error: nil, retry: retry)),
            (2, .notice(text: "Stopped retrying. Your message is still queued; send again to try it.", isError: false)),
        ])
        #expect(
            notices(mirror).map(\.text) == [
                "Fake Agent couldn't be reached (Network error).",
                "Stopped retrying. Your message is still queued; send again to try it.",
            ])
        #expect(mirror.state.turns.last?.stopReason == .error)
        #expect(mirror.state.turns.last?.endedAt == at(0.1))
    }

    @Test("Codex's command cut off by a host crash reads interrupted after the reload, not exit -1")
    func cutOffCommandAfterReload() throws {
        // codex-acp 2.2.2 replaying a command its agent process went away during (captured 2026-10-20).
        let replay = [
            #"{"jsonrpc":"2.0","method":"session/update","params":{"sessionId":"01a158ad-a414-7140-8dbc-83fff80e8824","update":{"sessionUpdate":"user_message_chunk","messageId":"01a158ad-ace6-7313-acde-c3d1fcbeb00e","content":{"type":"text","text":"Run this exact shell command and wait for it to finish: for i in $(seq 1 30); do echo tick $i; sleep 1; done. Then reply with only the last line it printed. Don't change any files."}}}}"#,
            #"{"jsonrpc":"2.0","method":"session/update","params":{"sessionId":"01a158ad-a414-7140-8dbc-83fff80e8824","update":{"sessionUpdate":"tool_call","toolCallId":"exec-96e0af4d-4547-43f1-9d87-034a4950f85c","name":"exec_command","kind":"execute","title":"for i in $(seq 1 30); do echo tick $i; sleep 1; done","status":"failed","content":[{"type":"terminal","terminalId":"exec-96e0af4d-4547-43f1-9d87-034a4950f85c"}],"rawInput":{"command":"for i in $(seq 1 30); do echo tick $i; sleep 1; done","cwd":"/tmp/turn-life/work"},"_meta":{"terminal_info":{"cwd":"/tmp/turn-life/work","terminal_id":"exec-96e0af4d-4547-43f1-9d87-034a4950f85c"}}}}}"#,
            #"{"jsonrpc":"2.0","method":"session/update","params":{"sessionId":"01a158ad-a414-7140-8dbc-83fff80e8824","update":{"sessionUpdate":"tool_call_update","toolCallId":"exec-96e0af4d-4547-43f1-9d87-034a4950f85c","_meta":{"terminal_output_delta":{"data":"tick 1\ntick 2\ntick 3\n","terminal_id":"exec-96e0af4d-4547-43f1-9d87-034a4950f85c"},"terminal_exit":{"exit_code":-1,"signal":null,"terminal_id":"exec-96e0af4d-4547-43f1-9d87-034a4950f85c"}}}}}"#,
        ]
        let note = RecoveryNote(cause: .hostStopped, action: .resumed, agentName: "Codex", interruptedAt: at(0))
        let mirror = mirror(
            [(1, .reset(loading: true))] + (try replay.map { (1, try decoded($0)) }) + [
                (2, .loaded), (2, .recovered(note)),
                (
                    2,
                    .prompt(
                        PromptEcho(text: "[Native] Your previous turn was interrupted", origin: .recovery, shown: false)
                    )
                ),
                (3, chunk("I'll check whether it finished.")),
            ])
        let call = try #require(calls(mirror).first)
        #expect(call.status == .interrupted)
        #expect(call.exitCode == -1)
        #expect(notices(mirror).map(\.text).first?.hasPrefix("Native's background host stopped unexpectedly") == true)
    }

    @Test("A recovery that couldn't reload interrupts what was running, at the interruption")
    func recoveryWithoutReload() throws {
        let note = RecoveryNote(
            cause: .agentStopped, action: .failed, agentName: "Codex", interruptedAt: at(9), problem: "not installed")
        let mirror = mirror([
            (0, .reset(loading: false)),
            (0, .prompt(PromptEcho(text: "Run it", requestID: UUID()))),
            (
                2,
                .update(
                    .object([
                        "sessionUpdate": .string("tool_call"), "toolCallId": .string("exec-1"),
                        "kind": .string("execute"), "title": .string("sleep 30"), "status": .string("in_progress"),
                    ]))
            ),
            (9, .recovered(note)),
        ])
        let call = try #require(calls(mirror).first)
        #expect(call.status == .interrupted)
        #expect(call.finishedAt == at(9))
    }

    @Test("A request the transcript doesn't show never rewrites the finished turn before it")
    func unshownRequestKeepsTheTurnBefore() throws {
        let mirror = mirror([
            (0, .reset(loading: false)),
            (0, .prompt(PromptEcho(text: "hello", requestID: UUID()))),
            (2, chunk("echo: hello")),
            (2, .turnEnded(stopReason: "end_turn")),
            (100, .prompt(PromptEcho(text: "A task's message", origin: .task, requestID: UUID(), shown: false))),
            (110, chunk("No.")),
            (110, .turnEnded(stopReason: "refusal")),
        ])
        let turn = try #require(mirror.state.turns.first)
        #expect(turn.stopReason == .endTurn)
        #expect(turn.duration == 2)
    }

    @Test("The answer to a request sent after a stop isn't output after the stop")
    func unshownRequestAfterAStop() {
        let mirror = mirror([
            (0, .reset(loading: false)),
            (0, .prompt(PromptEcho(text: "stubborn 60", requestID: UUID()))),
            (3, .turnEnded(stopReason: "cancelled")),
            (5, .prompt(PromptEcho(text: "Status?", origin: .task, requestID: UUID(), shown: false))),
            (6, chunk("All done.")),
            (6, .turnEnded(stopReason: "end_turn")),
        ])
        #expect(mirror.state.turns.map(\.isLateOutput) == [false])
        #expect(notices(mirror).map(\.text) == ["Stopped."])
    }

    @Test("A request the transcript doesn't show is retried without reopening the turn before it")
    func unshownRequestRetry() throws {
        let id = UUID()
        let retry = DeliveryRetry(agentName: agent, reason: "Network error", delay: 5)
        let mirror = mirror([
            (0, .reset(loading: false)),
            (0, .prompt(PromptEcho(text: "hello", requestID: UUID()))),
            (1, .turnEnded(stopReason: "end_turn")),
            (10, .prompt(PromptEcho(text: "A task's message", origin: .task, requestID: id, shown: false))),
            (10.1, .turnFailed(message: retry.waitingText, error: nil, retry: retry)),
            (15, .prompt(PromptEcho(text: "A task's message", origin: .queued, requestID: id, shown: false))),
            (16, chunk("Done.")),
            (16, .turnEnded(stopReason: "end_turn")),
        ])
        let turn = try #require(mirror.state.turns.first)
        #expect(turn.stopReason == .endTurn)
        #expect(turn.duration == 1)
        #expect(notices(mirror).map(\.text) == ["Reconnected to Fake Agent, and your message went through on retry."])
    }

    @Test("Output after Native stopped waiting is a turn of its own, after the stopped turn's ending")
    func lateOutputAfterAnAbandonedStop() throws {
        let mirror = mirror([
            (0, .reset(loading: false)),
            (0, .prompt(PromptEcho(text: "stubborn 60", requestID: UUID()))),
            (1, chunk("tick 1\n")),
            (12, .turnEnded(stopReason: "cancelled")),
            (12, .notice(text: "Fake Agent didn't confirm it stopped, so Native stopped waiting.", isError: false)),
            (13, chunk("tick 43\n")),
        ])
        let turns = mirror.state.turns
        #expect(turns.map(\.isLateOutput) == [false, true])
        #expect(turns.first?.stopReason == .cancelled)
        #expect(turns.first?.endedAt == at(12))
        #expect(
            notices(mirror).map(\.text) == [
                "Stopped.", "Fake Agent didn't confirm it stopped, so Native stopped waiting.",
                "The agent kept going after the stop.",
            ])
    }
}
