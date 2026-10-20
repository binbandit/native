import SwiftUI

/// Tasks the user pinned, in a small section above the projects, in their own order:
/// drag to reorder, Unpin from the context menu or a swipe. A pinned task shows only here.
struct PinnedSection<TaskAccessory: View>: View {
    @Environment(AppModel.self) private var model
    /// The pinned tasks to show: all of them, or those the Needs You filter keeps.
    let sessions: [SessionSummary]
    /// Every pinned task's place in the pin order, filtered out or not.
    let order: [SessionKey: Int]
    let drag: SidebarDragState
    let taskAccessory: (SessionSummary) -> TaskAccessory
    let select: (SessionKey) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.xs) {
            SectionHeader("Pinned")
            ForEach(sessions) { summary in
                let row = SidebarDragState.Item.pinned(summary.id)
                let index = order[summary.id] ?? 0
                SessionRow(
                    summary: summary, indent: .flat, isPinned: true,
                    canMoveUp: index > 0, canMoveDown: index < order.count - 1,
                    accessory: taskAccessory(summary)
                ) {
                    select(summary.id)
                }
                .equatable()
                .sidebarDraggable(row, title: model.title(for: summary), state: drag)
                .sidebarDropTarget(row, state: drag, onDrop: model.applySidebarDrop)
            }
        }
        .padding(.bottom, DS.Space.md)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Pinned")
    }
}
