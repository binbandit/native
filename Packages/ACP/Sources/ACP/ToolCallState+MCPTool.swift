import Foundation

/// The MCP server and tool behind a tool call.
public struct MCPToolCall: Hashable, Sendable {
    public let server: String
    public let tool: String
    /// The call's name as the agent sent it: `mcp__native__setup_status` from Claude Code,
    /// `mcp.native.setup_status` from Codex.
    public let rawName: String
}

extension ToolCallState {
    /// The MCP tool the call runs, when it's an MCP call.
    ///
    /// Claude Code names it `mcp__<server>__<tool>`. codex-acp 2.2.2 sends it as an `execute` call
    /// titled `mcp.<server>.<tool>`, marked `_meta.is_mcp_tool_call`, with the server and tool in
    /// `rawInput` beside the arguments.
    public var mcpTool: MCPToolCall? {
        if let name, let call = MCPToolCall(claudeCodeName: name) {
            return call
        }
        guard meta?["is_mcp_tool_call"] == .bool(true) || title.hasPrefix("mcp.") else { return nil }
        if let server = rawInput?["server"]?.stringValue, let tool = rawInput?["tool"]?.stringValue,
            !server.isEmpty, !tool.isEmpty
        {
            return MCPToolCall(server: server, tool: tool, rawName: "mcp.\(server).\(tool)")
        }
        return MCPToolCall(codexTitle: title)
    }

    /// The arguments the MCP tool was called with: Codex nests them in `rawInput.arguments`, Claude
    /// Code sends them as the input itself.
    public var mcpArguments: JSONValue? {
        guard mcpTool != nil else { return nil }
        if rawInput?["server"] != nil, rawInput?["tool"] != nil { return rawInput?["arguments"] }
        return rawInput
    }

    /// What the MCP tool returned, as text: codex-acp 2.2.2 puts the MCP result (or the error) in
    /// `rawOutput` rather than the content.
    public var mcpResultText: String? {
        guard mcpTool != nil, let output = rawOutput else { return nil }
        if let message = output["error"]?["message"]?.stringValue ?? output["error"]?.stringValue {
            return message
        }
        guard case .array(let blocks) = output["result"]?["content"] else { return nil }
        let texts = blocks.compactMap { $0["text"]?.stringValue }
        return texts.isEmpty ? nil : texts.joined(separator: "\n")
    }
}

extension MCPToolCall {
    /// `mcp__<server>__<tool>`: the server runs to the next `__` and the tool is the rest.
    init?(claudeCodeName name: String) {
        guard name.hasPrefix("mcp__") else { return nil }
        let rest = name.dropFirst("mcp__".count)
        guard let separator = rest.range(of: "__"), separator.lowerBound > rest.startIndex else { return nil }
        let tool = rest[separator.upperBound...]
        guard !tool.isEmpty else { return nil }
        self.init(server: String(rest[..<separator.lowerBound]), tool: String(tool), rawName: name)
    }

    /// `mcp.<server>.<tool>`, for a call whose input doesn't name them.
    init?(codexTitle title: String) {
        let rest = title.dropFirst("mcp.".count)
        guard title.hasPrefix("mcp."), let dot = rest.firstIndex(of: "."), dot > rest.startIndex else { return nil }
        let tool = rest[rest.index(after: dot)...]
        guard !tool.isEmpty, !tool.contains(" ") else { return nil }
        self.init(server: String(rest[..<dot]), tool: String(tool), rawName: title)
    }
}
