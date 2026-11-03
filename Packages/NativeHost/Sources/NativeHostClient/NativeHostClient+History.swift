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

    public func joinHistory(_ params: JoinHistoryParams) async throws -> TaskHistorySummary {
        try await call(HostProtocol.Method.joinHistory, params)
    }

    public func missingHistory(of session: HostSessionID) async throws -> TaskHistoryMissing {
        try await call(HostProtocol.Method.missingHistory, SessionParams(sessionID: session))
    }

    /// What a session's transcript shows of the agents before it: the newest `limit` messages and tool
    /// calls its handoff considered that other agents produced, and whether older ones were left out.
    /// Nil when the session has no handoff, which is final: a handoff's range never changes.
    public func handoffRuns(
        of session: HostSessionID, limit: Int
    ) async throws -> (runs: [TaskHistoryRun], omitsEarlier: Bool)? {
        let summary = try await historySummary(of: session)
        guard let handoff = summary.handoff else { return nil }
        return try await runs(of: session, in: summary, at: handoff, after: handoff.from, limit: limit)
    }

    /// What a context marker in a session's transcript shows: what the other agents did that its
    /// transfer considered, after what the transcript showed above it (its top, and the markers in
    /// `earlierMarkers`). Nil when the marker stands for no transfer of this session.
    public func markerRuns(
        of session: HostSessionID, markerID: String, earlierMarkers: Set<String>, limit: Int
    ) async throws -> (runs: [TaskHistoryRun], omitsEarlier: Bool)? {
        let summary = try await historySummary(of: session)
        guard let transfer = summary.transfer(forMarker: markerID) else { return nil }
        return try await runs(
            of: session, in: summary, at: transfer,
            after: summary.shownAfter(transfer, earlierMarkers: earlierMarkers), limit: limit)
    }

    private func runs(
        of session: HostSessionID, in summary: TaskHistorySummary, at transfer: TaskHistoryTransfer, after start: Int,
        limit: Int
    ) async throws -> (runs: [TaskHistoryRun], omitsEarlier: Bool) {
        // Enough of the newest items to fill the limit once reasoning and endings are left out.
        let after = max(start, transfer.through - limit * 4)
        let items = try await readHistory(
            ReadHistoryParams(sessionID: session, after: after, through: transfer.through))
        let latest = TaskHistoryRun.latest(
            summary.runs(of: items.filter { $0.seq > start }, at: transfer), limit: limit)
        return (latest.runs, latest.omitsEarlier || after > start)
    }

    public func withdrawHistory(of session: HostSessionID) async throws -> TaskHistorySummary {
        try await call(HostProtocol.Method.withdrawHistory, SessionParams(sessionID: session))
    }

    public func recordHandoff(_ params: HandoffHistoryParams) async throws -> TaskHistorySummary {
        try await call(HostProtocol.Method.handoffHistory, params)
    }
}
