import Foundation
import Testing

@testable import ACP

/// codex-acp 2.2.2 with `gpt-6.1-sol`, a client declaring no terminals, asked to run `ls` and then
/// `for i in 1 2 3; do echo line $i; sleep 1; done` (captured 2026-10-18). Live, the output comes in
/// `_meta.terminal_output_delta` chunks (this capture lost `line 1` on the wire); a `session/load`
/// replays it as one chunk.
private enum CodexTerminalWire {
    static let listStart =
        #"{"jsonrpc":"2.0","method":"session/update","params":{"sessionId":"01a14e42-5fc2-76d2-8c39-a9c75291a5cc","update":{"sessionUpdate":"tool_call","toolCallId":"exec-b4210acc-8c8d-4703-9231-bbe4a8ce1817","name":"exec_command","kind":"read","title":"List files","status":"in_progress"}}}"#
    static let listEnd =
        #"{"jsonrpc":"2.0","method":"session/update","params":{"sessionId":"01a14e42-5fc2-76d2-8c39-a9c75291a5cc","update":{"sessionUpdate":"tool_call_update","toolCallId":"exec-b4210acc-8c8d-4703-9231-bbe4a8ce1817","status":"completed","rawOutput":{"exit_code":0},"_meta":{"terminal_output_delta":{"data":"notes.txt\nsrc\n","terminal_id":"exec-b4210acc-8c8d-4703-9231-bbe4a8ce1817"}}}}}"#
    static let loopStart =
        #"{"jsonrpc":"2.0","method":"session/update","params":{"sessionId":"01a14e42-cc17-7562-91b2-3292eb20e227","update":{"sessionUpdate":"tool_call","toolCallId":"exec-8f607785-e9f0-4f65-bea2-735ea2db44a9","name":"exec_command","kind":"execute","title":"for i in 1 2 3; do echo line $i; sleep 1; done","status":"in_progress","content":[{"type":"terminal","terminalId":"exec-8f607785-e9f0-4f65-bea2-735ea2db44a9"}],"rawInput":{"command":"for i in 1 2 3; do echo line $i; sleep 1; done","cwd":"/tmp/stabilize-capture"},"_meta":{"terminal_info":{"cwd":"/tmp/stabilize-capture","terminal_id":"exec-8f607785-e9f0-4f65-bea2-735ea2db44a9"}}}}}"#
    static let loopChunks = [
        #"{"jsonrpc":"2.0","method":"session/update","params":{"sessionId":"01a14e42-cc17-7562-91b2-3292eb20e227","update":{"sessionUpdate":"tool_call_update","toolCallId":"exec-8f607785-e9f0-4f65-bea2-735ea2db44a9","_meta":{"terminal_output_delta":{"data":"line 2\n","terminal_id":"exec-8f607785-e9f0-4f65-bea2-735ea2db44a9"}}}}}"#,
        #"{"jsonrpc":"2.0","method":"session/update","params":{"sessionId":"01a14e42-cc17-7562-91b2-3292eb20e227","update":{"sessionUpdate":"tool_call_update","toolCallId":"exec-8f607785-e9f0-4f65-bea2-735ea2db44a9","_meta":{"terminal_output_delta":{"data":"line 3\n","terminal_id":"exec-8f607785-e9f0-4f65-bea2-735ea2db44a9"}}}}}"#,
        #"{"jsonrpc":"2.0","method":"session/update","params":{"sessionId":"01a14e42-cc17-7562-91b2-3292eb20e227","update":{"sessionUpdate":"tool_call_update","toolCallId":"exec-8f607785-e9f0-4f65-bea2-735ea2db44a9","status":"completed","_meta":{"terminal_exit":{"exit_code":0,"signal":null,"terminal_id":"exec-8f607785-e9f0-4f65-bea2-735ea2db44a9"}}}}}"#,
    ]
    static let loopReplay = [
        #"{"jsonrpc":"2.0","method":"session/update","params":{"sessionId":"01a14e42-cc17-7562-91b2-3292eb20e227","update":{"sessionUpdate":"tool_call","toolCallId":"exec-8f607785-e9f0-4f65-bea2-735ea2db44a9","name":"exec_command","kind":"execute","title":"for i in 1 2 3; do echo line $i; sleep 1; done","status":"completed","content":[{"type":"terminal","terminalId":"exec-8f607785-e9f0-4f65-bea2-735ea2db44a9"}],"rawInput":{"command":"for i in 1 2 3; do echo line $i; sleep 1; done","cwd":"/tmp/stabilize-capture"},"_meta":{"terminal_info":{"cwd":"/tmp/stabilize-capture","terminal_id":"exec-8f607785-e9f0-4f65-bea2-735ea2db44a9"}}}}}"#,
        #"{"jsonrpc":"2.0","method":"session/update","params":{"sessionId":"01a14e42-cc17-7562-91b2-3292eb20e227","update":{"sessionUpdate":"tool_call_update","toolCallId":"exec-8f607785-e9f0-4f65-bea2-735ea2db44a9","_meta":{"terminal_output_delta":{"data":"line 1\nline 2\nline 3\n","terminal_id":"exec-8f607785-e9f0-4f65-bea2-735ea2db44a9"},"terminal_exit":{"exit_code":0,"signal":null,"terminal_id":"exec-8f607785-e9f0-4f65-bea2-735ea2db44a9"}}}}}"#,
    ]
}

struct TerminalOutputTests {
    private static let loopID = "exec-8f607785-e9f0-4f65-bea2-735ea2db44a9"

    private func state(after lines: [String]) throws -> SessionState {
        var state = SessionState()
        state.appendUserMessage("Run it")
        for line in lines {
            guard case .sessionUpdate(let notification) = try Wire.event(line) else {
                Issue.record("Expected a session update")
                continue
            }
            state.apply(notification.update)
        }
        return state
    }

    @Test func listingKeepsItsOutput() throws {
        let state = try state(after: [CodexTerminalWire.listStart, CodexTerminalWire.listEnd])
        let call = try #require(state.call("exec-b4210acc-8c8d-4703-9231-bbe4a8ce1817"))
        #expect(call.terminalOutput == "notes.txt\nsrc\n")
        #expect(call.status == .completed)
    }

    @Test func liveChunksAppendInOrder() throws {
        let running = try #require(try state(after: [CodexTerminalWire.loopStart]).call(Self.loopID))
        #expect(running.terminalOutput == nil)
        let state = try state(after: [CodexTerminalWire.loopStart] + CodexTerminalWire.loopChunks)
        let call = try #require(state.call(Self.loopID))
        #expect(call.terminalOutput == "line 2\nline 3\n")
        // The chunks don't linger in the merged metadata, which keeps everything else.
        #expect(call.meta?["terminal_output_delta"] == nil)
        #expect(call.meta?["terminal_exit"]?["exit_code"] == .number(0))
        #expect(call.meta?["terminal_info"] != nil)
    }

    @Test func replayedCommandHasItsWholeOutput() throws {
        let call = try #require(try state(after: CodexTerminalWire.loopReplay).call(Self.loopID))
        #expect(call.terminalOutput == "line 1\nline 2\nline 3\n")
        #expect(call.meta?["terminal_exit"]?["exit_code"] == .number(0))
    }
}

private extension SessionState {
    func call(_ id: String) -> ToolCallState? {
        items.lazy.compactMap { item -> ToolCallState? in
            guard case .toolCall(let call) = item, call.id == id else { return nil }
            return call
        }.first
    }
}
