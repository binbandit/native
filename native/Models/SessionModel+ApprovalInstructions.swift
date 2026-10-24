import ACP

extension SessionModel {
    /// Stale views never answer a newer request that reused the tool-call ID.
    func chooseApproval(_ option: PermissionOption, for call: ToolCallState) async {
        guard let current = permissionRequests.first(where: { $0.id == call.id }),
            current == call, current.permission?.options.contains(option) == true
        else { return }
        await choose(option, forToolCall: call.id)
    }

    /// ACP cannot edit a tool call. Secure the instruction in the prompt queue before declining,
    /// leaving the request and the user's words in place if submission fails.
    func instructInstead(_ text: String, for call: ToolCallState) async throws {
        guard phase == .prompting,
            let current = permissionRequests.first(where: { $0.id == call.id }), current == call,
            let reject = current.permission?.options.first(where: { $0.kind == .rejectOnce })
                ?? current.permission?.options.first(where: \.isRejection)
        else { throw ApprovalInstructionError.requestEnded }
        try await submit(text, .queue)
        await chooseApproval(reject, for: call)
    }
}

private enum ApprovalInstructionError: Error {
    case requestEnded
}
