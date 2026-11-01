import Foundation

/// What a participant has in its context (docs/decisions/2026-11-01-one-task-history.md,
/// "Watermarks and coverage"): the items it produced or received as prompts, and the items
/// delivered transfers conveyed. Considering an item is not conveying it.
public enum TaskHistoryCoverage {
    /// The `seq` ranges of this history that delivered transfers conveyed to `participant`.
    public static func conveyed(
        to participant: Int, by transfers: [TaskHistoryTransfer], in history: TaskHistoryID
    ) -> [ClosedRange<Int>] {
        transfers.filter { $0.target == participant && $0.state == .delivered && $0.sourceHistory == history }
            .flatMap(\.conveyed)
    }

    public static func hasSeen(_ item: TaskHistoryItem, participant: Int, conveyed: [ClosedRange<Int>]) -> Bool {
        item.source == participant || conveyed.contains { $0.contains(item.seq) }
    }

    /// The watermark after `seen`: how far, item by item, everything is in the participant's context.
    /// `items` are the history's items after `seen`, in order.
    public static func watermark(
        from seen: Int, over items: [TaskHistoryItem], participant: Int, conveyed: [ClosedRange<Int>]
    ) -> Int {
        var watermark = seen
        for item in items where item.seq > seen {
            guard item.seq == watermark + 1, hasSeen(item, participant: participant, conveyed: conveyed) else { break }
            watermark = item.seq
        }
        return watermark
    }

    /// The items after the watermark the participant has neither produced nor been given: what a
    /// return to it has to tell it.
    public static func missing(
        _ items: [TaskHistoryItem], participant: Int, conveyed: [ClosedRange<Int>]
    ) -> [TaskHistoryItem] {
        items.filter { !hasSeen($0, participant: participant, conveyed: conveyed) }
    }
}
