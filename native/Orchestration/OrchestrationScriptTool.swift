import Foundation
import MCP
import ScriptRuntime

/// Code mode for Native's MCP server: `run_script` runs an agent's JavaScript in the sandboxed
/// script runtime with read-only tools bound as `tools.<name>(…)`, so one call can gather and boil
/// down what would otherwise take a round trip through the model per tool call.
nonisolated enum OrchestrationScriptTool {
    /// The tools a script may call. Read-only only: the calls a script makes skip the per-call
    /// approval the agent's own tool calls get, so nothing that changes state is bound.
    static let scriptable: Set<String> = ["list_agents", "list_tasks", "get_task", "wait_for_task"]

    /// Added to the server's instructions when `run_script` is offered.
    static let instructions = " run_script runs JavaScript that calls the read-only tools, to check or wait on several tasks in one call."

    /// `run_script` over the scriptable `tools`, or nil without a runner: the app has none when it
    /// was built without cargo, or its runtime isn't signed into the App Sandbox.
    static func make(
        binding tools: [MCPTool<OrchestrationCaller>], runner: ScriptRunner? = try? ScriptRunner.embedded()
    ) -> MCPTool<OrchestrationCaller>? {
        guard let runner else { return nil }
        let bound = tools.filter { scriptable.contains($0.name) && $0.annotations.readOnly == true }
        let reference = ScriptReference.declarations(for: bound.map { binding($0) { _ in nil } })
        return MCPTool(
            name: "run_script",
            title: "Run script",
            description: """
                Run JavaScript that calls the tools listed below and return what it prints. Use it to gather \
                and condense in one call what would take several tool calls, such as checking every task and \
                reporting only the ones that need attention, or waiting on several tasks at once.

                The code is an ES module body: top-level await works. Print what you want back with \
                text(value) or console.log(value); objects print as JSON, and nothing else is returned. Each \
                tool takes one object argument and resolves with its structured result; a failed call \
                rejects with its error. The script runs in an isolated sandbox with no files, network, \
                modules, require, process or fetch: these tools are its only way out. Pass long text through \
                `inputs` and read it as inputs.<name>. Errors report the line and column in your code.

                Tools:
                \(reference)
                """,
            inputSchema: [
                "type": "object",
                "properties": [
                    "code": ["type": "string", "description": "The script, JavaScript."],
                    "inputs": [
                        "type": "object",
                        "additionalProperties": ["type": "string"],
                        "description": "Text the script reads as inputs.<name>, kept out of its source.",
                    ],
                    "timeout_seconds": [
                        "type": "integer",
                        "minimum": 1,
                        "maximum": 240,
                        "description": "How long the script may run, in seconds. Defaults to 60.",
                    ],
                ],
                "required": ["code"],
                "additionalProperties": false,
            ],
            outputSchema: [
                "type": "object",
                "properties": [
                    "output": ["type": "string", "description": "What the script printed, a line per text() call."],
                    "tool_calls": ["type": "integer"],
                    "failure": [
                        "type": "object",
                        "properties": [
                            "kind": ["type": "string"],
                            "message": ["type": "string"],
                            "line": ["type": "integer"],
                            "column": ["type": "integer"],
                        ],
                    ],
                ],
                "required": ["output", "tool_calls"],
            ],
            annotations: MCPToolAnnotations(readOnly: true, openWorld: false),
            arguments: RunScriptArguments.self
        ) { caller, arguments in
            // MCP clients give up on a silent call after a few minutes (Claude Code after five).
            let seconds = min(max(arguments.timeoutSeconds ?? 60, 1), 240)
            let bindings = bound.map { tool in
                binding(tool) { input in
                    let result = await tool(caller, arguments: try JSON(encoding: input))
                    if result.isError { throw ScriptToolError(result.text) }
                    return try result.structuredContent.map { try ScriptJSON(encoding: $0) } ?? .string(result.text)
                }
            }
            let result = try await runner.run(
                arguments.code, bindings: bindings, inputs: arguments.inputs ?? [:],
                limits: ScriptLimits(time: .seconds(seconds)))
            return MCPToolResult(text: result.report, structuredContent: try JSON(encoding: result.summary), isError: !result.succeeded)
        }
    }

    private static func binding(
        _ tool: MCPTool<OrchestrationCaller>, call: @escaping @Sendable (ScriptJSON) async throws -> ScriptJSON
    ) -> ScriptBinding {
        ScriptBinding(
            path: [tool.name],
            summary: tool.description,
            inputSchema: try? ScriptJSON(encoding: tool.inputSchema),
            outputSchema: tool.outputSchema.flatMap { try? ScriptJSON(encoding: $0) },
            handler: call)
    }
}

private nonisolated struct RunScriptArguments: Decodable, Sendable {
    var code: String
    var inputs: [String: String]?
    var timeoutSeconds: Int?

    enum CodingKeys: String, CodingKey {
        case code, inputs
        case timeoutSeconds = "timeout_seconds"
    }
}
