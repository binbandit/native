import ACP
import Foundation
import NativeHostClient
import NativeHostProtocol

extension SessionModel {
    /// Keep the exact ask pending if transport fails; the receipt follows the acknowledgement.
    func respondToPermission(_ option: PermissionOption, call: ToolCallState) async throws {
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

    /// The caller only advances after both the queued instruction and rejection are acknowledged.
    func instructBeforeDecliningPermission(_ text: String, call: ToolCallState) async throws {
        guard phase == .prompting, permissionRequests.contains(call),
            let reject = call.permission?.options.first(where: { $0.kind == .rejectOnce })
                ?? call.permission?.options.first(where: \.isRejection)
        else { throw SendError.busy }
        let text = PromptQuote.trimmed(text)
        let previous = Set(queuedPrompts.map(\.id))
        try await submit(text, .queue)
        let queued = queuedPrompts.first { !previous.contains($0.id) && $0.text == text }?.id
        do {
            try await respondToPermission(reject, call: call)
        } catch {
            if let queued { removeQueued(queued) }
            throw error
        }
    }
}
