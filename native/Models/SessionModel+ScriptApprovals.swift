import ACP
import Foundation

/// Calls Native makes on a session's behalf, such as the tool calls of a script the agent ran
/// through Native's `run_script`. They show in the session's transcript as tool calls of their own,
/// and when they need the user, Native raises the same approval card the agent's calls get and
/// answers it itself.
extension SessionModel {
    /// The current value of the agent's `mode` setting, such as "default" or "bypassPermissions".
    var permissionMode: String? {
        configOptions.lazy.compactMap { option -> String? in
            guard option.category == "mode" || option.id == "mode", case .select(let current, _) = option.kind else {
                return nil
            }
            return current
        }.first
    }

    /// The agent's `toolName` call still running, newest first: the call a script's own calls
    /// belong under. Agents name MCP tools their own way (`mcp__native__run_script`), so the end
    /// of the name or title is what's matched.
    func runningToolCall(named toolName: String) -> String? {
        state.items.reversed().lazy.compactMap { item -> String? in
            guard case .toolCall(let call) = item, !call.status.isFinished,
                [call.name, call.title].contains(where: { $0?.hasSuffix(toolName) == true })
            else { return nil }
            return call.id
        }.first
    }

    /// Adds or updates a call Native makes for the session.
    func recordNativeToolCall(_ call: ToolCallUpdate) {
        state.apply(.toolCall(call))
    }

    /// Asks the user about `call` with the approval card, and waits for the answer until
    /// `deadline`. Nil when the deadline passes (the card is withdrawn), the turn is cancelled or
    /// the waiting task is.
    func requestNativeApproval(
        for call: ToolCallUpdate, options: [PermissionOption], until deadline: ContinuousClock.Instant
    ) async -> PermissionOption? {
        let requestID = NativeApprovals.newID()
        state.requestPermission(
            RequestPermissionRequest(sessionId: id, toolCall: call, options: options), id: requestID)
        return await NativeApprovals.wait(for: requestID, until: deadline) { [weak self] in
            self?.state.resolvePermission(toolCallID: call.toolCallId)
        }
    }
}

/// The approvals Native raised itself and is waiting on, by request id. `SessionModel` hands them
/// their answer instead of sending it to the agent, which never asked.
enum NativeApprovals {
    private static let prefix = "native-approval-"
    private static var waiting: [RequestID: CheckedContinuation<PermissionOption?, Never>] = [:]

    static func newID() -> RequestID {
        .string(prefix + UUID().uuidString)
    }

    /// Whether Native raised the request with `id` rather than an agent.
    static func isNative(_ id: RequestID) -> Bool {
        guard case .string(let value) = id else { return false }
        return value.hasPrefix(prefix)
    }

    /// Hands a waiting request its answer; nil rejects it.
    static func answer(_ id: RequestID, with option: PermissionOption?) {
        waiting.removeValue(forKey: id)?.resume(returning: option)
    }

    static func wait(
        for id: RequestID, until deadline: ContinuousClock.Instant, withdraw: @escaping @MainActor () -> Void
    ) async -> PermissionOption? {
        let expiry = Task {
            guard (try? await Task.sleep(until: deadline)) != nil, waiting[id] != nil else { return }
            withdraw()
            answer(id, with: nil)
        }
        defer { expiry.cancel() }
        return await withTaskCancellationHandler {
            await withCheckedContinuation { waiting[id] = $0 }
        } onCancel: {
            Task { @MainActor in
                guard waiting[id] != nil else { return }
                withdraw()
                answer(id, with: nil)
            }
        }
    }
}
