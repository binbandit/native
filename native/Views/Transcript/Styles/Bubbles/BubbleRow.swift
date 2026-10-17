import ACP
import Foundation

/// Which side of the conversation a bubble sits on.
nonisolated enum BubbleSide: Hashable, Sendable {
    /// The agent.
    case leading
    /// The user.
    case trailing
}

/// Where a bubble sits in a run of bubbles from the same side. Only the last one has a tail.
nonisolated struct BubbleGroupPosition: Hashable, Sendable {
    var isFirst: Bool
    var isLast: Bool

    static let single = BubbleGroupPosition(isFirst: true, isLast: true)
}

/// A transcript row as Bubbles shows it: messages become grouped bubbles, and runs of tool
/// activity become one tray between them.
enum BubbleRow: Identifiable {
    case message(TranscriptMessage, BubbleSide, BubbleGroupPosition)
    case thought(TranscriptMessage)
    /// Consecutive tool calls and folded explorations, none waiting for approval.
    case activity([TranscriptRow])
    /// A tool call waiting for approval, on its own so it stands out.
    case approval(ToolCallState)
    case notice(TranscriptNotice)
    case subagent(SubagentState)
    case sessionMessage(SessionMessage)

    var id: String {
        switch self {
        case .message(let message, _, _), .thought(let message): TranscriptItem.message(message).id
        // The first row never changes as the run grows, so the tray keeps its identity.
        case .activity(let rows): "activity-\(rows.first?.id ?? "")"
        case .approval(let call): TranscriptItem.toolCall(call).id
        case .notice(let notice): TranscriptItem.notice(notice).id
        case .subagent(let subagent): TranscriptItem.subagent(subagent).id
        case .sessionMessage(let message): TranscriptItem.sessionMessage(message).id
        }
    }

    /// The side of a bubble, for spacing and transitions; nil for everything else.
    var bubbleSide: BubbleSide? {
        if case .message(_, let side, _) = self { side } else { nil }
    }

    /// Lays out transcript rows as bubbles: groups consecutive messages from the same side and
    /// gathers runs of tool activity into trays.
    static func plan(_ rows: [TranscriptRow]) -> [BubbleRow] {
        var plan: [BubbleRow] = []
        var activity: [TranscriptRow] = []

        func flushActivity() {
            if !activity.isEmpty {
                plan.append(.activity(activity))
                activity.removeAll()
            }
        }

        for row in rows {
            switch row {
            case .item(.toolCall(let call)) where call.permission != nil:
                flushActivity()
                plan.append(.approval(call))
            case .exploration, .item(.toolCall):
                activity.append(row)
            case .item(.message(let message)):
                flushActivity()
                switch message.role {
                case .user: plan.append(.message(message, .trailing, .single))
                case .agent: plan.append(.message(message, .leading, .single))
                case .thought: plan.append(.thought(message))
                }
            case .item(.notice(let notice)):
                flushActivity()
                plan.append(.notice(notice))
            case .item(.subagent(let subagent)):
                flushActivity()
                plan.append(.subagent(subagent))
            case .item(.sessionMessage(let message)):
                flushActivity()
                plan.append(.sessionMessage(message))
            }
        }
        flushActivity()
        return grouped(plan)
    }

    /// Marks where each bubble sits in its run of same-side bubbles.
    private static func grouped(_ plan: [BubbleRow]) -> [BubbleRow] {
        plan.indices.map { index in
            guard case .message(let message, let side, _) = plan[index] else { return plan[index] }
            let previous = index > plan.startIndex ? plan[index - 1].bubbleSide : nil
            let next = index < plan.endIndex - 1 ? plan[index + 1].bubbleSide : nil
            return .message(message, side, BubbleGroupPosition(isFirst: previous != side, isLast: next != side))
        }
    }

    /// Bubbles in a group sit close; a change of speaker or kind of row gets room.
    static func spacing(between previous: BubbleRow, and next: BubbleRow) -> CGFloat {
        switch (previous.bubbleSide, next.bubbleSide) {
        case (let before?, let after?) where before == after: BubbleMetrics.groupSpacing
        case (let before?, let after?) where before != after: BubbleMetrics.speakerSpacing
        default: BubbleMetrics.rowSpacing
        }
    }
}
