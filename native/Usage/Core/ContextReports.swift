import ACP
import Foundation
import Observation

/// The latest `/context` report of each session, taken on request while the session is idle.
/// Reports live here rather than in the transcript: the command runs hidden and costs no tokens.
@Observable
final class ContextReports {
    private(set) var reports: [SessionKey: ContextReport] = [:]
    private var refreshing: Set<SessionKey> = []
    private var failed: Set<SessionKey> = []
    /// When each session's last turn ended; reports taken before then are stale.
    private var turnEnds: [SessionKey: Date] = [:]

    func report(for key: SessionKey) -> ContextReport? {
        reports[key]
    }

    func status(of session: some ContextReporting) -> ContextReportStatus {
        let key = session.contextKey
        guard session.canReportContext else { return .unsupported }
        if refreshing.contains(key) { return .refreshing }
        guard session.isIdleForContext else { return .busy }
        if failed.contains(key) { return .failed }
        let isStale = reports[key].map { report in turnEnds[key].map { report.capturedAt < $0 } ?? false } ?? true
        return .ready(isStale: isStale)
    }

    func noteTurnEnded(_ key: SessionKey, at date: Date = .now) {
        turnEnds[key] = date
    }

    func forget(_ key: SessionKey) {
        reports[key] = nil
        failed.remove(key)
        turnEnds[key] = nil
    }

    func refresh(_ session: some ContextReporting) async {
        let key = session.contextKey
        guard session.canReportContext, session.isIdleForContext, !refreshing.contains(key) else { return }
        refreshing.insert(key)
        defer { refreshing.remove(key) }
        if let text = try? await session.runHiddenCommand("/context"), let report = ContextReport.parse(text) {
            reports[key] = report
            failed.remove(key)
        } else {
            failed.insert(key)
        }
    }
}
