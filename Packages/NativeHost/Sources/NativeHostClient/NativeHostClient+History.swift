import ACP
import Foundation
import NativeHostProtocol

// One task history (docs/decisions/2026-11-01-one-task-history.md): what every agent session of a
// session's task has done and seen, as the host keeps it.
extension NativeHostClient {
    public func historySummary(of session: HostSessionID) async throws -> TaskHistorySummary {
        try await call(HostProtocol.Method.historySummary, SessionParams(sessionID: session))
    }

    public func readHistory(_ params: ReadHistoryParams) async throws -> [TaskHistoryItem] {
        try await call(HostProtocol.Method.readHistory, params)
    }
}
