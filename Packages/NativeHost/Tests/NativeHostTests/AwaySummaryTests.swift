import ACP
import Foundation
import NativeHostClient
import NativeHostProtocol
import Testing

@Suite("While you were away")
struct AwaySummaryTests {
    private let fix = HostSessionID()
    private let docs = HostSessionID()
    private let tests = HostSessionID()
    private let start = Date(timeIntervalSince1970: 1_800_000_000)

    private func entry(
        _ id: Int64, _ kind: ActivityEntry.Kind, _ session: HostSessionID?, detail: String? = nil,
        recovery: RecoveryNote? = nil
    ) -> ActivityEntry {
        ActivityEntry(
            id: id, at: start.addingTimeInterval(Double(id) * 60), sessionID: session, agentID: "claude",
            agentSessionID: session.map { SessionID($0.description) }, kind: kind, subject: "Task \(id)",
            detail: detail, recovery: recovery)
    }

    private func summary(_ id: HostSessionID, needsApproval: Bool = false) -> HostSessionSummary {
        HostSessionSummary(
            id: id, agentID: "claude", agentName: "Claude Code", agentSessionID: nil, cwd: "/tmp", phase: .idle,
            needsApproval: needsApproval)
    }

    private func note(
        _ cause: RecoveryNote.Cause, _ action: RecoveryNote.Action = .resumed, at minute: Double = 0
    )
        -> RecoveryNote
    {
        RecoveryNote(
            cause: cause, action: action, agentName: "Claude Code", interruptedAt: start.addingTimeInterval(minute))
    }

    @Test("Tasks that need the user come first, and the headline counts each outcome once")
    func foldsOutcomes() throws {
        let summary = try #require(
            AwaySummary(
                entries: [
                    entry(1, .recovered, fix, recovery: note(.agentStopped)),
                    entry(2, .turnFinished, fix),
                    entry(3, .approvalNeeded, docs, detail: "Run swift test"),
                    entry(4, .turnFailed, tests, detail: "Rate limited"),
                ],
                sessions: [summary(fix), summary(docs, needsApproval: true), summary(tests)]))

        #expect(summary.items.map(\.id) == [docs, tests, fix])
        #expect(summary.items.map(\.outcome) == [.needsApproval("Run swift test"), .failed("Rate limited"), .finished])
        #expect(summary.items.last?.recoveries.count == 1)
        #expect(summary.lastEntryID == 4)
        #expect(
            summary.headline
                == "1 task finished, 1 needs your approval, and 1 failed. Claude Code stopped once and Native resumed it."
        )
    }

    @Test("An approval given elsewhere, the user's own stops and host bookkeeping aren't news")
    func leavesOutWhatIsNotNews() {
        let summary = AwaySummary(
            entries: [
                entry(1, .hostStarted, nil, detail: "Resuming 1 interrupted task"),
                entry(2, .approvalNeeded, docs, detail: "Edit README.md"),
                entry(3, .updateRequested, nil),
            ],
            sessions: [summary(docs, needsApproval: false)])
        #expect(summary == nil)
    }

    @Test("One host crash that interrupted two tasks counts once; an agent's own crashes count each time")
    func countsIncidents() throws {
        let summary = try #require(
            AwaySummary(
                entries: [
                    entry(1, .recovered, fix, recovery: note(.hostStopped, at: 5)),
                    entry(2, .recovered, docs, recovery: note(.hostStopped, at: 5)),
                    entry(3, .recovered, tests, recovery: note(.agentStopped, at: 9)),
                    entry(4, .recovered, tests, recovery: note(.agentStopped, at: 12)),
                ],
                sessions: [summary(fix), summary(docs), summary(tests)]))
        #expect(
            summary.headline
                == "3 tasks are still working. Native's background host stopped unexpectedly, and Native resumed your tasks. Claude Code stopped twice and Native resumed it each time."
        )
    }

    @Test("A task Native couldn't bring back reads as failed, with the reason")
    func failedRecovery() throws {
        var failed = note(.agentStopped, .failed)
        failed.problem = "claude isn't installed"
        let summary = try #require(
            AwaySummary(entries: [entry(1, .recovered, fix, recovery: failed)], sessions: [summary(fix)]))
        #expect(summary.items.first?.outcome == .failed(failed.sentence()))
        #expect(summary.headline == "1 task failed.")
    }
}
