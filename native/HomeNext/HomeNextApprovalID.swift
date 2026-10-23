import ACP

/// Tool call IDs and JSON-RPC request IDs are only unique within their owning session.
struct HomeNextApprovalID: Equatable {
    let session: SessionKey
    let call: String
    let request: RequestID

    init?(session: SessionModel?, call: ToolCallState?) {
        guard let session, let call, let permission = call.permission else { return nil }
        self.session = session.key
        self.call = call.id
        request = permission.requestID
    }
}
