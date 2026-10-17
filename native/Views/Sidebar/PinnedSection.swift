import SwiftUI

/// Tasks the user pinned, in a small section above the projects (Orca's Pinned), in their own order:
/// drag to reorder, Unpin from the context menu or a swipe. A pinned task shows only here.
struct PinnedSection<TaskAccessory: View>: View {
    @Environment(AppModel.self) private var model
    /// The pinned tasks to show: all of them, or those the Needs You filter keeps.
    let sessions: [SessionSummary]
    let drag: SidebarDragState
    let taskAccessory: (SessionSummary) -> TaskAccessory
    let select: (SessionKey) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.xs) {
            SectionHeader("Pinned")
            ForEach(sessions) { summary in
                let row = SidebarDragState.Item.pinned(summary.id)
                SessionRow(summary: summary, indent: .flat, accessory: taskAccessory(summary)) {
                    select(summary.id)
                }
                .sidebarDraggable(row, title: model.title(for: summary), state: drag)
                .sidebarDropTarget(row, state: drag, onDrop: model.applySidebarDrop)
            }
        }
        .padding(.bottom, DS.Space.md)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Pinned")
    }
}
