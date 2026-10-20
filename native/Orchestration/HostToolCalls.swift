import ACP
import Foundation
import MCP
import NativeHostClient
import NativeHostProtocol
import NativeOrchestration
import Synchronization

/// Calls Native's host's own tools for one of its sessions: what `run_script` binds when the app
/// runs a script for a session the host serves, so a script's `tools.list_tasks()` sees the host's
/// tasks.
nonisolated final class HostToolCalls: Sendable {
    private let client = Mutex<NativeHostClient?>(nil)

    func use(_ client: NativeHostClient) {
        self.client.withLock { $0 = client }
    }

    func call(_ tool: String, for caller: OrchestrationCaller, arguments: JSON) async -> MCPToolResult {
        guard let client = client.withLock({ $0 }) else { return .error("Native's host isn't connected.") }
        do {
            let result = try await client.callTool(
                CallToolParams(
                    sessionID: HostSessionID(caller.clientID), tool: tool,
                    arguments: try JSONDecoder().decode(JSONValue.self, from: JSONEncoder().encode(arguments))))
            return MCPToolResult(
                text: result.text, structuredContent: try result.structuredContent.map { try JSON(encoding: $0) },
                isError: result.isError)
        } catch {
            return .error(error.localizedDescription)
        }
    }
}
