import Foundation
import MCP
import NativeOrchestration

/// Executes production handlers, recording the observable tool boundary for the grader.
public actor EvalSession {
    public nonisolated let tools: [MCPTool<OrchestrationCaller>]
    private let caller: OrchestrationCaller
    private var transcript: EvalTranscript
    private let maximumCalls: Int

    public init(_ test: ToolUseCase, maximumCalls: Int = 12) {
        let runtime = EvalRuntime(test)
        caller = runtime.caller
        tools = OrchestrationTools.all(TaskOrchestrator(runtime: runtime))
        transcript = EvalTranscript(caseID: test.id)
        self.maximumCalls = maximumCalls
    }

    public func call(_ name: String, arguments: JSON) async -> JSON {
        guard transcript.calls.count < maximumCalls else {
            transcript.completion = .stepLimit
            return [
                "content": [["type": "text", "text": "Eval tool-call limit reached. End your turn."]], "isError": true,
            ]
        }
        let result: MCPToolResult
        if let tool = tools.first(where: { $0.name == name }) {
            let invalid = ToolInputValidation.failures(arguments, schema: tool.inputSchema)
            result =
                invalid.isEmpty
                ? await tool(caller, arguments: arguments) : .error(invalid.joined(separator: "; "))
        } else {
            result = .error("Unknown Native tool: \(name)")
        }
        var wire: [String: JSON] = [
            "content": [["type": "text", "text": .string(result.text)]], "isError": .bool(result.isError),
        ]
        wire["structuredContent"] = result.structuredContent
        transcript.calls.append(
            .init(
                tool: name, arguments: arguments, result: .object(wire), isError: result.isError))
        return .object(wire)
    }

    public func trace(finalText: String = "") -> EvalTranscript {
        var copy = transcript
        copy.finalText = finalText
        return copy
    }
}
