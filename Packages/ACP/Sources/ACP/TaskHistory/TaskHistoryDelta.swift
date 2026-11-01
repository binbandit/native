import Foundation

/// What an agent session missed while other agents worked on its task, as the budgeted handoff's
/// draft (docs/decisions/2026-11-01-one-task-history.md, "Switching back with a delta"): the history
/// supplies the items, `ContextTransferSelector` chooses and renders them, and the receipt says which
/// were carried. An item's `position` is its `seq`, so the receipt maps back to the history.
public enum TaskHistoryDelta {
    /// The items a returning participant hasn't seen, as context items. Messages and replies go as
    /// text, plan steps as a plan; reasoning and tool state are never replayed, and say so.
    public static func draft(
        _ items: [TaskHistoryItem], participants: [TaskHistoryParticipant]
    ) -> ContextTransfer.Draft {
        let sources = Dictionary(
            participants.map {
                ($0.ordinal, ContextTransfer.SessionReference(agent: $0.agentID, session: $0.agentSessionID))
            }, uniquingKeysWith: { first, _ in first })
        var draft = ContextTransfer.Draft(items: [])
        for item in items {
            guard let source = sources[item.source] else { continue }
            func include(_ kind: ContextTransfer.Kind, _ text: String, id: String = "history/\(item.seq)") {
                draft.items.append(
                    .init(reference: .init(source: source, id: id, kind: kind, position: item.seq), text: text))
            }
            func omit(_ reason: ContextTransfer.Omission.Reason) {
                draft.omitted.append(.init(source: source, id: "history/\(item.seq)", reason: reason))
            }
            switch item.body {
            case .user(let message):
                include(.user, message.text)
                for (index, _) in message.attachments.enumerated() {
                    draft.omitted.append(
                        .init(
                            source: source, id: "history/\(item.seq)/attachment/\(index)",
                            reason: .attachmentNotReplayed))
                }
            case .agent(let text):
                include(.agent, text)
            case .plan(let steps):
                include(.plan, steps.map { "- [\($0.status)] \($0.content)" }.joined(separator: "\n"))
            case .thought:
                omit(.reasoning)
            case .tool:
                omit(.toolState)
            case .turnEnded, .unknown:
                continue
            }
        }
        return draft
    }

    /// The items of `considered` a delivered delta covers: those it carried, and those it never
    /// replays (reasoning, tool state, turn endings). Only what its budget left out stays missing, to
    /// be offered again next time.
    public static func covered(by receipt: ContextTransfer.Receipt, considered: [Int]) -> [ClosedRange<Int>] {
        let leftOut = Set(
            receipt.omitted.filter { $0.reason == .budget }.compactMap { Int($0.id.dropFirst("history/".count)) })
        return ranges(considered.filter { !leftOut.contains($0) })
    }

    /// Ascending values as the fewest ranges.
    static func ranges(_ values: [Int]) -> [ClosedRange<Int>] {
        var ranges: [ClosedRange<Int>] = []
        for value in values.sorted() {
            if let last = ranges.last, value <= last.upperBound + 1 {
                ranges[ranges.count - 1] = last.lowerBound...max(last.upperBound, value)
            } else {
                ranges.append(value...value)
            }
        }
        return ranges
    }
}
