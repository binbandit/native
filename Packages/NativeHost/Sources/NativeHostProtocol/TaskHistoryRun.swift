import ACP
import Foundation

/// Items one other participant of a task produced, in order: what a session's transcript shows under
/// that agent's name before its own conversation (docs/decisions/2026-11-01-one-task-history.md, "The
/// transcript"). The session's own items are in its own replay, so each item appears once.
public struct TaskHistoryRun: Hashable, Sendable, Identifiable {
    public var participant: TaskHistoryParticipant
    public var items: [TaskHistoryItem]

    public init(participant: TaskHistoryParticipant, items: [TaskHistoryItem]) {
        self.participant = participant
        self.items = items
    }

    public var id: Int { items.first?.seq ?? 0 }

    /// The newest `limit` items of `runs`, in their runs, and whether older ones were left out: a
    /// transcript shows the end of a long earlier conversation, not all of it.
    public static func latest(_ runs: [TaskHistoryRun], limit: Int) -> (runs: [TaskHistoryRun], omitsEarlier: Bool) {
        var budget = limit
        var kept: [TaskHistoryRun] = []
        for var run in runs.reversed() {
            guard budget > 0 else { return (kept, true) }
            let omits = run.items.count > budget
            run.items = Array(run.items.suffix(budget))
            budget -= run.items.count
            kept.insert(run, at: 0)
            if omits { return (kept, true) }
        }
        return (kept, false)
    }
}

extension TaskHistorySummary {
    /// The context this session was given when it joined its task: the handoff of the change of agent
    /// that started it. Nil for the task's first session, and for one whose change was undone.
    public var handoff: TaskHistoryTransfer? {
        transfers.first {
            $0.target == current && $0.sourceHistory == id && $0.state != .superseded
                && ($0.strategy == .client || $0.strategy == .full)
        }
    }

    /// What a transcript shows for `transfer`, from the items it considered: those another participant
    /// produced that a transcript shows, one run per participant in order.
    public func runs(of items: [TaskHistoryItem], at transfer: TaskHistoryTransfer) -> [TaskHistoryRun] {
        let byOrdinal = Dictionary(participants.map { ($0.ordinal, $0) }, uniquingKeysWith: { first, _ in first })
        var runs: [TaskHistoryRun] = []
        for item in items
        where item.seq > transfer.from && item.seq <= transfer.through && item.source != current
            && item.transcriptItem != nil
        {
            if runs.last?.participant.ordinal == item.source {
                runs[runs.count - 1].items.append(item)
            } else if let participant = byOrdinal[item.source] {
                runs.append(TaskHistoryRun(participant: participant, items: [item]))
            }
        }
        return runs
    }
}
