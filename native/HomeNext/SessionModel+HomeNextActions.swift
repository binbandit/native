import ACP
import NativeHostClient
import NativeHostProtocol

extension SessionModel {
    /// Keep the ask on Home if transport fails; the receipt follows the acknowledgement.
    func answerHomeNextPermission(_ option: PermissionOption, call: ToolCallState) async throws {
        guard let permission = call.permission,
            permissionRequests.contains(where: { $0.id == call.id && $0.permission == permission }),
            permission.options.contains(option)
        else { throw SendError.busy }
        if NativeApprovals.isNative(permission.requestID) {
            state.resolvePermission(toolCallID: call.id)
            NativeApprovals.answer(permission.requestID, with: option)
        } else if let host {
            let params = RespondPermissionParams(sessionID: host.id, toolCallID: call.id, optionID: option.optionId)
            try await host.request { try await $0.respondPermission(params) }
            // A new request may already have reused this tool call's ID while we awaited the host.
            if state.permissionRequests.first(where: { $0.id == call.id })?.permission?.requestID
                == permission.requestID
            {
                state.resolvePermission(toolCallID: call.id)
            }
        } else if let connection {
            try await connection.respond(
                to: permission.requestID, with: RequestPermissionResponse.selected(optionId: option.optionId))
            if state.permissionRequests.first(where: { $0.id == call.id })?.permission?.requestID
                == permission.requestID
            {
                state.resolvePermission(toolCallID: call.id)
            }
        } else {
            throw SendError.disconnected
        }
    }

    var canRetryHomeNext: Bool {
        taskStatus == .failed && acceptsPrompts && (host != nil || phase == .idle)
    }

    /// Ask it to check completed work before continuing, without replacing the user's draft.
    func retryHomeNext(turnID: String?) async throws {
        guard canRetryHomeNext, state.turns.last?.id == turnID else { throw SendError.busy }
        try await submit(
            "Continue the interrupted task from where it stopped. Check what already completed before repeating any work.",
            .queue)
    }
}
