import ACP
import Foundation
import MCP
import NativeHostProtocol
import NativeOrchestration

// Tools only the Mac app can answer: `setup_status` reports the app's own state, and `run_script`
// runs in the app's script runtime with the app's MCP library bound. The app offers them in
// `_native/tasks/configure`; the host lists them for its sessions and passes each call to that app
// (`_native/tasks/app_tool_call`, answered with `_native/tasks/app_tool_result`). With the app
// closed they stay listed, since agents read a session's tools once, and a call says why it can't
// run and what still works, so the agent can carry on.
extension HostTasks {
    /// How long a listing may take before the tool is listed as the app declared it.
    static let listingPatience: Duration = .seconds(1)
    /// The longest a call may take: `run_script` runs for at most 240 seconds.
    static let callPatience: Duration = .seconds(270)

    /// The app's tools, as MCP tools whose calls go to the app.
    func relayedTools() -> [MCPTool<OrchestrationCaller>] {
        appTools.compactMap { definition in
            guard let inputSchema = try? JSON(encoding: definition.inputSchema) else { return nil }
            var tool = MCPTool(
                name: definition.name, title: definition.title, description: definition.description,
                inputSchema: inputSchema, outputSchema: definition.outputSchema.flatMap { try? JSON(encoding: $0) },
                annotations: Self.annotations(definition.annotations), arguments: JSON.self
            ) { [weak self] caller, arguments in
                guard let self else { throw MCPToolError("Native's host is stopping.") }
                return try await call(definition.name, for: caller, arguments: arguments)
            }
            // What the tool says can depend on the session (which MCP servers a script reaches).
            tool.listing = { [weak self] caller in
                let listed = await self?.relay(.listing, definition.name, for: caller, patience: Self.listingPatience)
                let definition = listed?.listing ?? definition
                return .init(description: definition.description, annotations: Self.annotations(definition.annotations))
            }
            return tool
        }
    }

    private func call(_ name: String, for caller: OrchestrationCaller, arguments: JSON) async throws -> MCPToolResult {
        let arguments = try JSONValue(encoding: arguments)
        guard
            let answer = await relay(.call, name, for: caller, arguments: arguments, patience: Self.callPatience),
            let result = answer.result
        else {
            throw MCPToolError(
                "\(name) runs in Native's app on \(core.configuration.machineName), which isn't open right now, so it "
                    + "can't answer. Native's other tools work without it (list_tasks, wait_for_task, get_task, "
                    + "send_message and the rest): use them directly, or ask the user to open Native and try again.")
        }
        return MCPToolResult(
            text: result.text, structuredContent: result.structuredContent.flatMap { try? JSON(encoding: $0) },
            isError: result.isError)
    }

    /// Passes a call or listing to the app that offered the tool and waits for its answer: nil when
    /// it isn't connected, goes away, or takes longer than `patience`.
    private func relay(
        _ kind: AppToolCall.Kind, _ tool: String, for caller: OrchestrationCaller, arguments: JSONValue = .object([:]),
        patience: Duration
    ) async -> AppToolResult? {
        guard let provider = appToolProvider, let client = core.clients[provider] else { return nil }
        let call = AppToolCall(
            kind: kind, tool: tool, sessionID: HostSessionID(caller.clientID), agentID: caller.agent,
            cwd: caller.cwd.path(percentEncoded: false), arguments: arguments)
        let id = call.callID
        return await withTaskCancellationHandler {
            await withCheckedContinuation { (continuation: CheckedContinuation<AppToolResult?, Never>) in
                guard !Task.isCancelled else { return continuation.resume(returning: nil) }
                appToolCalls[id] = continuation
                client.notify(HostProtocol.Method.appToolCall, call)
                // Gives up after `patience`, or as soon as the app goes away.
                Task { [weak self] in
                    let deadline = ContinuousClock.now + patience
                    while ContinuousClock.now < deadline {
                        try? await Task.sleep(for: .milliseconds(250))
                        guard let self, appToolCalls[id] != nil else { return }
                        if core.clients[provider] == nil { break }
                    }
                    self?.receive(AppToolResult(callID: id), answering: false)
                }
            }
        } onCancel: {
            Task { @HostActor [weak self] in self?.receive(AppToolResult(callID: id), answering: false) }
        }
    }

    /// The app's answer to a call or listing passed to it.
    func receive(_ answer: AppToolResult) {
        receive(answer, answering: true)
    }

    private func receive(_ answer: AppToolResult, answering: Bool) {
        appToolCalls.removeValue(forKey: answer.callID)?.resume(returning: answering ? answer : nil)
    }

    /// One of the host's own tools, called for a session.
    func callOwnTool(_ params: CallToolParams) async throws -> ToolResult {
        guard let caller = caller(of: params.sessionID.rawValue) else { throw HostTaskError.closed }
        guard let tool = ownTools.first(where: { $0.name == params.tool }) else {
            throw HostTaskError.noTool(params.tool)
        }
        let result = await tool(caller, arguments: try JSON(encoding: params.arguments))
        return ToolResult(
            text: result.text, structuredContent: try result.structuredContent.map(JSONValue.init(encoding:)),
            isError: result.isError)
    }

    nonisolated private static func annotations(_ json: JSONValue?) -> MCPToolAnnotations {
        MCPToolAnnotations(
            readOnly: json?["readOnlyHint"]?.boolValue, destructive: json?["destructiveHint"]?.boolValue,
            idempotent: json?["idempotentHint"]?.boolValue, openWorld: json?["openWorldHint"]?.boolValue)
    }
}

extension JSONValue {
    /// Converts any `Encodable` value, such as an MCP result.
    init(encoding value: some Encodable) throws {
        self = try JSONDecoder().decode(JSONValue.self, from: JSONEncoder().encode(value))
    }

    fileprivate var boolValue: Bool? {
        if case .bool(let value) = self { value } else { nil }
    }
}
