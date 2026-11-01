import ACP
import Foundation
import NativeHostProtocol
import Testing

/// What a session's transcript shows of the rest of its task: the items its handoff considered that
/// another agent produced, once each.
struct TaskHistoryRunTests {
    private let history = TaskHistoryID()

    /// Claude Code (1) answered, Codex (2) took over with a handoff and answered, and Claude Code's
    /// new conversation (3) joined after it.
    private var participants: [TaskHistoryParticipant] {
        [(1, "claude-code"), (2, "codex"), (3, "claude-code")].map {
            TaskHistoryParticipant(ordinal: $0.0, agentID: $0.1, agentSessionID: SessionID("s\($0.0)"))
        }
    }

    private let items: [TaskHistoryItem] = [
        TaskHistoryItem(seq: 1, source: 1, body: .user(.init(text: "fix the tests"))),
        TaskHistoryItem(
            seq: 2, source: 1,
            body: .tool(.init(id: "t1", title: "swift test", kind: "execute", status: "failed", input: "swift test"))),
        TaskHistoryItem(seq: 3, source: 1, body: .agent("Two tests fail.")),
        TaskHistoryItem(seq: 4, source: 1, body: .turnEnded(stopReason: "end_turn")),
        TaskHistoryItem(seq: 5, source: 2, body: .user(.init(text: "carry on"))),
        TaskHistoryItem(seq: 6, source: 2, body: .thought("reading the failures")),
        TaskHistoryItem(seq: 7, source: 2, body: .agent("Fixed both.")),
        TaskHistoryItem(seq: 8, source: 2, body: .turnEnded(stopReason: "end_turn")),
    ]

    private func summary(current: Int, transfers: [TaskHistoryTransfer]) -> TaskHistorySummary {
        TaskHistorySummary(id: history, head: 8, participants: participants, current: current, transfers: transfers)
    }

    private func handoff(
        to target: Int, through: Int, state: TaskHistoryTransfer.State = .delivered
    )
        -> TaskHistoryTransfer
    {
        TaskHistoryTransfer(
            sourceHistory: history, target: target, from: 0, through: through, conveyed: [], strategy: .client,
            state: state)
    }

    @Test("A session's handoff is the context it was given when it joined, unless that was undone")
    func handoffs() {
        let codex = handoff(to: 2, through: 4)
        let undone = handoff(to: 3, through: 8, state: .superseded)
        let delta = TaskHistoryTransfer(
            sourceHistory: history, target: 3, from: 0, through: 8, conveyed: [], strategy: .delta)
        #expect(summary(current: 2, transfers: [codex, undone, delta]).handoff == codex)
        #expect(summary(current: 3, transfers: [codex, undone, delta]).handoff == nil)
        #expect(summary(current: 1, transfers: [codex]).handoff == nil)
        // Another task's context never stands for this one's.
        let elsewhere = TaskHistoryTransfer(
            sourceHistory: TaskHistoryID(), target: 2, from: 0, through: 4, conveyed: [], strategy: .client)
        #expect(summary(current: 2, transfers: [elsewhere]).handoff == nil)
    }

    @Test("The other agents' messages and tool calls in the handoff's range show, one run each")
    func runs() {
        let claude = handoff(to: 3, through: 8)
        let runs = summary(current: 3, transfers: [claude]).runs(of: items, at: claude)
        #expect(runs.map(\.participant.agentID) == ["claude-code", "codex"])
        #expect(runs.map { $0.items.map(\.seq) } == [[1, 2, 3], [5, 7]])

        // Codex's own items are in its own replay; only Claude Code's before the handoff show.
        let codex = handoff(to: 2, through: 4)
        let codexRuns = summary(current: 2, transfers: [codex]).runs(of: items, at: codex)
        #expect(codexRuns.map { $0.items.map(\.seq) } == [[1, 2, 3]])
    }

    @Test("A long earlier conversation shows its newest items, saying older ones are left out")
    func latest() {
        let transfer = handoff(to: 3, through: 8)
        let runs = summary(current: 3, transfers: [transfer]).runs(of: items, at: transfer)
        let cut = TaskHistoryRun.latest(runs, limit: 3)
        #expect(cut.runs.map { $0.items.map(\.seq) } == [[3], [5, 7]])
        #expect(cut.omitsEarlier)
        let whole = TaskHistoryRun.latest(runs, limit: 5)
        #expect(whole.runs == runs)
        #expect(!whole.omitsEarlier)
    }
}
