import ACP
import Foundation

/// A session's context as the indicator and breakdown read it: totals from the session, the
/// breakdown from `ContextReports`.
struct SessionContextSource: ContextSource {
    let session: SessionModel
    var reports = BuiltInPlugins.usage.contextReports

    var agentName: String { session.agentName }
    var usage: Usage? { session.usage }
    var isAwaitingContextUsage: Bool { session.contextCompactedAt != nil && session.usage == nil && report == nil }
    var report: ContextReport? {
        guard let report = reports.report(for: session.key) else { return nil }
        if let compactedAt = session.contextCompactedAt, report.capturedAt <= compactedAt { return nil }
        return report
    }
    var reportStatus: ContextReportStatus {
        let status = reports.status(of: session)
        if case .ready = status, report == nil { return .ready(isStale: true) }
        return status
    }
    var canCompact: Bool { session.acceptsPrompts && session.advertises("compact") }

    func refreshReport() async {
        await reports.refresh(session)
    }

    func compact() async {
        // A real turn, shown in the transcript: compaction changes the conversation.
        _ = try? await session.submit("/compact", .queue)
    }
}
