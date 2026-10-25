import Foundation

/// One task in the collapsed sidebar's list. Child asks keep their responding owner in `ask`.
struct TaskAttentionItem: Identifiable {
    let summary: SessionSummary
    let ask: TaskPeekAsk?

    var id: SessionKey { summary.id }
}
