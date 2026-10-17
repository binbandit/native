import ACP
import Foundation

/// A session's context as the indicator and breakdown read it: totals from the session, the
/// breakdown from `ContextReports`.
struct SessionContextSource: ContextSource {
    let session: SessionModel
    var reports: ContextReports = BuiltInPlugins.usage.contextReports

    var agentName: String { session.agentName }
    var usage: Usage? { session.state.usage }
    var report: ContextReport? { reports.report(for: session.key) }
    var reportStatus: ContextReportStatus { reports.status(of: session) }
    var canCompact: Bool { session.acceptsPrompts && session.advertises("compact") }

    func refreshReport() async {
        await reports.refresh(session)
    }

    func compact() async {
        // A real turn, shown in the transcript: compaction changes the conversation.
        _ = try? await session.submit("/compact", .queue)
    }
}
