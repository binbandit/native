import Foundation
import NativeHostProtocol
import Synchronization

// Native's tools for agents in the host, and the tasks sessions hand each other with them
// (docs/durability.md, "Native's tools in the host").
extension NativeHostClient {
    /// Every task the host remembers, oldest first.
    public func tasks() async throws -> [HostTask] {
        try await call(HostProtocol.Method.listTasks, EmptyMessage())
    }

    /// Who serves Native's tools for the host's sessions, and which of Native's skills are off.
    /// Only a Mac app on the host's machine may say.
    public func configureTasks(_ params: ConfigureTasksParams) async throws {
        let _: EmptyMessage = try await call(HostProtocol.Method.configureTasks, params)
    }

    /// Calls `handler` with every task the host starts or changes from now on, in order with the
    /// client's events. Like an event handler, it must never wait on a request to this client.
    public func addTaskHandler(_ handler: @escaping @Sendable (HostTask) async -> Void) {
        route(HostProtocol.Method.tasksChanged, make: TaskChangesRoute.init).add(handler)
    }

    /// Calls `handler` with every call of a tool this client offered in `configureTasks`, and every
    /// listing of one. It must return at once: answer later, with `answerAppTool`.
    public func addAppToolHandler(_ handler: @escaping @Sendable (AppToolCall) -> Void) {
        route(HostProtocol.Method.appToolCall, make: AppToolCallsRoute.init).add(handler)
    }

    /// Answers an `AppToolCall`.
    public func answerAppTool(_ answer: AppToolResult) async throws {
        let _: EmptyMessage = try await call(HostProtocol.Method.appToolResult, answer)
    }

    /// Calls one of the host's own tools for one of its sessions, as that session would.
    public func callTool(_ params: CallToolParams) async throws -> ToolResult {
        try await call(HostProtocol.Method.callTool, params)
    }
}

/// Hands each `_native/tasks/app_tool_call` to the handlers that answer them.
final class AppToolCallsRoute: HostNotificationRoute {
    private let handlers = Mutex<[@Sendable (AppToolCall) -> Void]>([])

    func add(_ handler: @escaping @Sendable (AppToolCall) -> Void) {
        handlers.withLock { $0.append(handler) }
    }

    func receive(_ message: JSONRPCPeer.Message) async {
        guard let call = try? message.params(as: AppToolCall.self) else { return }
        for handler in handlers.withLock({ $0 }) {
            handler(call)
        }
    }
}

/// Hands each `_native/tasks/changed` to the handlers that asked for task changes.
final class TaskChangesRoute: HostNotificationRoute {
    private let handlers = Mutex<[@Sendable (HostTask) async -> Void]>([])

    func add(_ handler: @escaping @Sendable (HostTask) async -> Void) {
        handlers.withLock { $0.append(handler) }
    }

    func receive(_ message: JSONRPCPeer.Message) async {
        guard let task = try? message.params(as: TaskChangedNotification.self).task else { return }
        for handler in handlers.withLock({ $0 }) {
            await handler(task)
        }
    }
}
