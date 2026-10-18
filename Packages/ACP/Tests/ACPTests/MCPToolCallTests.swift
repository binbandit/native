import Foundation
import Testing

@testable import ACP

/// An MCP call as codex-acp 2.2.2 sends it (`McpToolReporter` rendered by `AcpToolCallRenderer`):
/// an `execute` call titled `mcp.<server>.<tool>`, then an update with the MCP result in `rawOutput`.
private enum CodexMCPWire {
    static let toolCall =
        #"{"jsonrpc":"2.0","method":"session/update","params":{"sessionId":"01a14e13-0751-70b1-90d9-eb18ee6b63e9","update":{"sessionUpdate":"tool_call","toolCallId":"call_mcp_1","kind":"execute","title":"mcp.native.setup_status","status":"in_progress","rawInput":{"server":"native","tool":"setup_status","arguments":{"verbose":true}},"_meta":{"is_mcp_tool_call":true}}}}"#
    static let completed =
        #"{"jsonrpc":"2.0","method":"session/update","params":{"sessionId":"01a14e13-0751-70b1-90d9-eb18ee6b63e9","update":{"sessionUpdate":"tool_call_update","toolCallId":"call_mcp_1","status":"completed","rawInput":{"server":"native","tool":"setup_status","arguments":{"verbose":true}},"rawOutput":{"result":{"content":[{"type":"text","text":"Codex: ready"},{"type":"text","text":"Host: off"}]},"error":null},"_meta":{"is_mcp_tool_call":true}}}}"#
    static let failed =
        #"{"jsonrpc":"2.0","method":"session/update","params":{"sessionId":"01a14e13-0751-70b1-90d9-eb18ee6b63e9","update":{"sessionUpdate":"tool_call_update","toolCallId":"call_mcp_1","status":"failed","rawOutput":{"result":null,"error":{"message":"tool not found"}},"_meta":{"is_mcp_tool_call":true}}}}"#
}

struct MCPToolCallTests {
    private func state(after lines: String...) throws -> SessionState {
        var state = SessionState()
        state.appendUserMessage("Check setup")
        for line in lines {
            guard case .sessionUpdate(let notification) = try Wire.event(line) else {
                Issue.record("Expected a session update")
                continue
            }
            state.apply(notification.update)
        }
        return state
    }

    @Test func codexCallNamesItsServerAndTool() throws {
        let call = try #require(try state(after: CodexMCPWire.toolCall).call("call_mcp_1"))
        #expect(call.mcpTool == MCPToolCall(server: "native", tool: "setup_status", rawName: "mcp.native.setup_status"))
        #expect(call.mcpArguments == JSONValue.object(["verbose": .bool(true)]))
        #expect(call.mcpResultText == nil)
    }

    @Test func codexResultIsReadFromRawOutput() throws {
        let call = try #require(try state(after: CodexMCPWire.toolCall, CodexMCPWire.completed).call("call_mcp_1"))
        #expect(call.mcpResultText == "Codex: ready\nHost: off")
        let failed = try #require(try state(after: CodexMCPWire.toolCall, CodexMCPWire.failed).call("call_mcp_1"))
        #expect(failed.mcpResultText == "tool not found")
    }

    @Test func claudeCodeNameNamesItsServerAndTool() {
        var call = ToolCallState(id: "toolu_1")
        call.name = "mcp__native__get_skill"
        call.rawInput = .object(["name": .string("set-up-native")])
        #expect(call.mcpTool == MCPToolCall(server: "native", tool: "get_skill", rawName: "mcp__native__get_skill"))
        #expect(call.mcpArguments == JSONValue.object(["name": .string("set-up-native")]))
    }

    @Test func aTitleAloneStillCounts() {
        var call = ToolCallState(id: "call_2")
        call.title = "mcp.github.search_issues"
        #expect(call.mcpTool?.server == "github")
        #expect(call.mcpTool?.tool == "search_issues")
    }

    @Test func otherCallsAreNotMCP() throws {
        var command = ToolCallState(id: "exec_1")
        command.kind = .execute
        command.title = "mcp.sh --help"
        #expect(command.mcpTool == nil)
        var bash = ToolCallState(id: "toolu_2")
        bash.name = "Bash"
        #expect(bash.mcpTool == nil)
        bash.name = "mcp__"
        #expect(bash.mcpTool == nil)
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
