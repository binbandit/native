import Foundation
import Testing

@testable import ACP

/// codex-acp 2.2.2 with `gpt-6.1-sol` in read-only mode, asked to run `printf 'ship\n' > todo.txt`
/// (captured 2026-10-18). The `tool_call` carries the command as typed; the permission request that
/// follows replaces the title with "Run command" and the command with a JSON-encoded copy of it.
private enum CodexCommandWire {
    static let toolCall =
        #"{"jsonrpc":"2.0","method":"session/update","params":{"sessionId":"01a14e07-45f8-7383-8217-ac2e86f10e8b","update":{"sessionUpdate":"tool_call","toolCallId":"exec-1dbcba42-836a-46da-8c16-9fa44fca8e48","kind":"execute","title":"printf 'ship\\n' > todo.txt","status":"in_progress","content":[{"type":"terminal","terminalId":"exec-1dbcba42-836a-46da-8c16-9fa44fca8e48"}],"rawInput":{"command":"printf 'ship\\n' > todo.txt","cwd":"/tmp/companion2-work/sandbox"},"_meta":{"terminal_info":{"cwd":"/tmp/companion2-work/sandbox","terminal_id":"exec-1dbcba42-836a-46da-8c16-9fa44fca8e48"}}}}}"#
    static let permissionRequest =
        #"{"jsonrpc":"2.0","id":0,"method":"session/request_permission","params":{"sessionId":"01a14e07-45f8-7383-8217-ac2e86f10e8b","toolCall":{"toolCallId":"exec-1dbcba42-836a-46da-8c16-9fa44fca8e48","title":"Run command","rawInput":{"command":"\"printf 'ship\\\\n' > todo.txt\"","cwd":"/tmp/companion2-work/sandbox"},"kind":"execute","status":"pending"},"options":[{"optionId":"allow_once","name":"Yes, proceed","kind":"allow_once"},{"optionId":"accept_execpolicy_amendment","name":"Yes, and don't ask again for commands that start with `printf 'ship\\n' > todo.txt`","kind":"allow_always"},{"optionId":"cancel","name":"No, and tell Codex what to do differently","kind":"reject_once"}]}}"#
}

struct ShellCommandTests {
    private static let command = #"printf 'ship\n' > todo.txt"#

    @Test func codexPermissionRequestShowsTheCommandAsTyped() throws {
        var state = SessionState()
        state.appendUserMessage("Create todo.txt")
        guard case .sessionUpdate(let notification) = try Wire.event(CodexCommandWire.toolCall) else {
            Issue.record("Expected a tool call")
            return
        }
        state.apply(notification.update)
        let toolCallID = "exec-1dbcba42-836a-46da-8c16-9fa44fca8e48"
        #expect(state.call(toolCallID)?.shellCommand == Self.command)

        guard case .permissionRequest(let id, let request) = try Wire.event(CodexCommandWire.permissionRequest) else {
            Issue.record("Expected a permission request")
            return
        }
        state.requestPermission(request, id: id)
        let call = try #require(state.call(toolCallID))
        #expect(call.title == "Run command")
        #expect(call.rawInput?["command"]?.stringValue == "\"printf 'ship\\\\n' > todo.txt\"")
        #expect(call.shellCommand == Self.command)
    }

    @Test(arguments: [
        (#"["bash","-lc","git status --short"]"#, "git status --short"),
        (#"["/bin/zsh","-c","ls | head -3"]"#, "ls | head -3"),
        (#"["git","commit","-m","fix it's done"]"#, #"git commit -m 'fix it'\''s done'"#),
        (#"["ls"]"#, "ls"),
    ])
    func argvCommandsReadAsAShellLine(json: String, expected: String) throws {
        var call = ToolCallState(id: "call")
        call.rawInput = .object(["command": try Wire.json(json)])
        #expect(call.shellCommand == expected)
    }

    @Test func plainAndMissingCommands() throws {
        var call = ToolCallState(id: "call")
        #expect(call.shellCommand == nil)
        call.rawInput = .object(["command": .string(#""a b" "c""#)])
        #expect(call.shellCommand == #""a b" "c""#)
        call.rawInput = .object(["command": .string("  ")])
        #expect(call.shellCommand == nil)
        call.rawInput = .object(["command": .array([.string("ls"), .number(1)])])
        #expect(call.shellCommand == nil)
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
