import ACP
import Foundation
import NativeHostClient
import NativeHostProtocol

extension SessionModel {
    /// Keep the ask on Home if transport fails; the receipt follows the acknowledgement.
    func answerHomeNextPermission(_ option: PermissionOption, call: ToolCallState) async throws {
        guard let permission = call.permission,
            permissionRequests.contains(call),
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

    /// Home only advances after both the queued instruction and rejection are acknowledged.
    func instructHomeNext(_ text: String, call: ToolCallState) async throws {
        guard phase == .prompting, permissionRequests.contains(call),
            let reject = call.permission?.options.first(where: { $0.kind == .rejectOnce })
                ?? call.permission?.options.first(where: \.isRejection)
        else { throw SendError.busy }
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let previous = Set(queuedPrompts.map(\.id))
        try await submit(text, .queue)
        let queued = queuedPrompts.first { !previous.contains($0.id) && $0.text == text }?.id
        do {
            try await answerHomeNextPermission(reject, call: call)
        } catch {
            if let queued { removeQueued(queued) }
            throw error
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
