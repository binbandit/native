import NativeHostProtocol

extension NativeHostClient {
    /// Exports only approval metadata from an authenticated local admin connection.
    public func approvalAudit(
        cursor: HostApprovalAuditCursor? = nil, limit: Int = 100
    ) async throws -> HostApprovalAuditPage {
        try await call(HostProtocol.Method.exportApprovalAudit, ExportApprovalAuditParams(cursor: cursor, limit: limit))
    }
}
