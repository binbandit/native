import Foundation
import Testing

@testable import ACP

/// codex-acp 2.2.2 driving Codex through one prompt that lists files, reads one, searches, runs a
/// command, fails one, and searches the web. Verbatim apart from the project path and user name.
enum CodexToolWire {
    static let lines = [
        #"{"jsonrpc":"2.0","method":"session/update","params":{"sessionId":"01a15233-d007-7fb1-8aaa-1764ce9b4d44","update":{"sessionUpdate":"tool_call","toolCallId":"exec-22338a01-0465-4d5b-b935-f17f2603d5c3","name":"exec_command","kind":"read","title":"List files","status":"in_progress"}}}"#,
        #"{"jsonrpc":"2.0","method":"session/update","params":{"sessionId":"01a15233-d007-7fb1-8aaa-1764ce9b4d44","update":{"sessionUpdate":"tool_call_update","toolCallId":"exec-22338a01-0465-4d5b-b935-f17f2603d5c3","status":"completed","rawOutput":{"exit_code":0},"_meta":{"terminal_output_delta":{"data":"total 24\ndrwxr-xr-x@  5 me  staff  160 Oct 19 14:28 .\n-rw-r--r--@  1 me  staff   65 Oct 19 14:28 calc.py\n","terminal_id":"exec-22338a01-0465-4d5b-b935-f17f2603d5c3"}}}}}"#,
        #"{"jsonrpc":"2.0","method":"session/update","params":{"sessionId":"01a15233-d007-7fb1-8aaa-1764ce9b4d44","update":{"sessionUpdate":"tool_call","toolCallId":"exec-8a26cae5-d027-4589-a0bc-bc83b3c81892","name":"exec_command","kind":"read","title":"Read file '/Users/me/project/calc.py'","status":"in_progress","locations":[{"path":"/Users/me/project/calc.py"}]}}}"#,
        #"{"jsonrpc":"2.0","method":"session/update","params":{"sessionId":"01a15233-d007-7fb1-8aaa-1764ce9b4d44","update":{"sessionUpdate":"tool_call","toolCallId":"exec-0b5d3d1b-3ad7-46b2-9c8c-9f1f07d543a0","name":"exec_command","kind":"search","title":"Search for 'def' in .","status":"in_progress"}}}"#,
        #"{"jsonrpc":"2.0","method":"session/update","params":{"sessionId":"01a15233-d007-7fb1-8aaa-1764ce9b4d44","update":{"sessionUpdate":"tool_call","toolCallId":"exec-0d506541-e41c-46a0-b533-deb68d753ec8","name":"exec_command","kind":"execute","title":"python3 -c 'print(sum(range(1000)))'","status":"in_progress","content":[{"type":"terminal","terminalId":"exec-0d506541-e41c-46a0-b533-deb68d753ec8"}],"rawInput":{"command":"python3 -c 'print(sum(range(1000)))'","cwd":"/Users/me/project"},"_meta":{"terminal_info":{"cwd":"/Users/me/project","terminal_id":"exec-0d506541-e41c-46a0-b533-deb68d753ec8"}}}}}"#,
        #"{"jsonrpc":"2.0","method":"session/update","params":{"sessionId":"01a15233-d007-7fb1-8aaa-1764ce9b4d44","update":{"sessionUpdate":"tool_call_update","toolCallId":"exec-0d506541-e41c-46a0-b533-deb68d753ec8","status":"completed","_meta":{"terminal_output_delta":{"data":"499500\n","terminal_id":"exec-0d506541-e41c-46a0-b533-deb68d753ec8"},"terminal_exit":{"exit_code":0,"signal":null,"terminal_id":"exec-0d506541-e41c-46a0-b533-deb68d753ec8"}}}}}"#,
        #"{"jsonrpc":"2.0","method":"session/update","params":{"sessionId":"01a15233-d007-7fb1-8aaa-1764ce9b4d44","update":{"sessionUpdate":"tool_call","toolCallId":"exec-6d9fe7cb-acb8-4071-a0b6-313204851627","name":"exec_command","kind":"read","title":"List files in 'does-not-exist'","status":"in_progress"}}}"#,
        #"{"jsonrpc":"2.0","method":"session/update","params":{"sessionId":"01a15233-d007-7fb1-8aaa-1764ce9b4d44","update":{"sessionUpdate":"tool_call_update","toolCallId":"exec-6d9fe7cb-acb8-4071-a0b6-313204851627","status":"failed","rawOutput":{"exit_code":1},"_meta":{"terminal_output_delta":{"data":"ls: does-not-exist: No such file or directory\n","terminal_id":"exec-6d9fe7cb-acb8-4071-a0b6-313204851627"}}}}}"#,
        #"{"jsonrpc":"2.0","method":"session/update","params":{"sessionId":"01a15233-d007-7fb1-8aaa-1764ce9b4d44","update":{"sessionUpdate":"tool_call","toolCallId":"exec-b6290148-eb0a-48d8-8eb2-9387957aec73","kind":"search","title":"Web search","status":"in_progress","rawInput":{"type":"webSearch","id":"exec-b6290148-eb0a-48d8-8eb2-9387957aec73","query":"","action":null}}}}"#,
        #"{"jsonrpc":"2.0","method":"session/update","params":{"sessionId":"01a15233-d007-7fb1-8aaa-1764ce9b4d44","update":{"sessionUpdate":"tool_call_update","toolCallId":"exec-b6290148-eb0a-48d8-8eb2-9387957aec73","title":"Web search: swift testing parameterized tests","status":"completed","rawInput":{"type":"webSearch","id":"exec-b6290148-eb0a-48d8-8eb2-9387957aec73","query":"swift testing parameterized tests","action":{"type":"search","query":"swift testing parameterized tests","queries":null}}}}}"#,
    ]
}

struct ToolCategoryTests {
    private func codexState() throws -> SessionState {
        var state = SessionState()
        state.appendUserMessage("Try every tool")
        for line in CodexToolWire.lines {
            guard case .sessionUpdate(let notification) = try Wire.event(line) else {
                Issue.record("Expected a session update")
                continue
            }
            state.apply(notification.update)
        }
        return state
    }

    @Test func codexCallsFollowTheirKindAndTitle() throws {
        let state = try codexState()
        let categories = try [
            "exec-22338a01-0465-4d5b-b935-f17f2603d5c3", "exec-8a26cae5-d027-4589-a0bc-bc83b3c81892",
            "exec-0b5d3d1b-3ad7-46b2-9c8c-9f1f07d543a0", "exec-0d506541-e41c-46a0-b533-deb68d753ec8",
            "exec-6d9fe7cb-acb8-4071-a0b6-313204851627", "exec-b6290148-eb0a-48d8-8eb2-9387957aec73",
        ]
        .map { try #require(state.call($0)).category }
        #expect(categories == [.read, .read, .search, .command, .read, .web])
    }

    @Test func codexReportsHowACommandExited() throws {
        let state = try codexState()
        #expect(state.call("exec-0d506541-e41c-46a0-b533-deb68d753ec8")?.exitCode == 0)
        #expect(state.call("exec-6d9fe7cb-acb8-4071-a0b6-313204851627")?.exitCode == 1)
        #expect(state.call("exec-b6290148-eb0a-48d8-8eb2-9387957aec73")?.exitCode == nil)
    }

    @Test(arguments: [
        ("Read", ToolCategory.read), ("LS", .read), ("Grep", .search), ("Glob", .search), ("Edit", .edit),
        ("MultiEdit", .edit), ("Write", .edit), ("NotebookEdit", .edit), ("Bash", .command), ("WebFetch", .web),
        ("WebSearch", .web), ("TodoWrite", .think), ("ExitPlanMode", .think), ("Task", .subagent),
        ("mcp__native__setup_status", .mcp),
    ])
    func claudeCodeToolsByName(name: String, category: ToolCategory) {
        var call = ToolCallState(id: "toolu_1")
        call.name = name
        // Claude Code's kinds don't always agree (`TodoWrite` is `think`, `Task` is `think` too).
        call.kind = .other
        #expect(call.category == category)
    }

    @Test(arguments: [
        (ToolKind.read, ToolCategory.read), (.search, .search), (.edit, .edit), (.delete, .edit), (.move, .edit),
        (.execute, .command), (.fetch, .web), (.think, .think), (.switchMode, .think),
    ])
    func otherAgentsByKind(kind: ToolKind, category: ToolCategory) {
        var call = ToolCallState(id: "call_1")
        call.kind = kind
        call.title = "Something"
        #expect(call.category == category)
    }

    @Test(arguments: [
        ("Read README.md", ToolCategory.read), ("List files in src", .read), ("Grep TODO", .search),
        ("Write notes.md", .edit), ("Apply patch", .edit), ("Run swift test", .command),
        ("Fetch https://example.com", .web), ("Web search: swift", .web), ("Plan the work", .think),
        ("Image generation", .other),
    ])
    func untypedCallsByTheirTitle(title: String, category: ToolCategory) {
        var call = ToolCallState(id: "call_1")
        call.title = title
        #expect(call.category == category)
    }

    @Test func mcpWinsOverTheKind() {
        var call = ToolCallState(id: "call_1")
        call.kind = .execute
        call.title = "mcp.github.search_issues"
        call.meta = .object(["is_mcp_tool_call": .bool(true)])
        #expect(call.category == .mcp)
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
