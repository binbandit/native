import Foundation
import NativeHostProtocol

// The client side of Native's tools in the host (`HostTasks.swift`): the task mirror clients keep
// (`_native/tasks/list`, then `_native/tasks/changed`), and the Mac app's choice of who serves them.
extension HostCore {
    /// A Mac app on this machine decides whether its host serves the tools (it does unless the app
    /// says otherwise) and which of Native's skills are off; a paired device has no say.
    func configureTasks(_ params: ConfigureTasksParams, by client: ClientLink) throws -> EmptyMessage {
        guard client.grants.isLocal else { throw HostError.notAuthorized("change how this host serves Native's tools") }
        try tasks.configure(params, from: client.id)
        return EmptyMessage()
    }

    /// The Mac app answered a call of one of its tools, or said how it lists one.
    func answerAppTool(_ result: AppToolResult, from client: ClientLink) throws -> EmptyMessage {
        guard client.grants.isLocal else { throw HostError.notAuthorized("answer Native's tools on this host") }
        tasks.receive(result)
        return EmptyMessage()
    }

    /// One of the host's own tools, called for a session: the Mac app's `run_script` binds them.
    func callTool(_ params: CallToolParams, from client: ClientLink) async throws -> ToolResult {
        guard client.grants.isLocal else { throw HostError.notAuthorized("call Native's tools on this host") }
        return try await tasks.callOwnTool(params)
    }
}
