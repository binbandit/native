import SwiftUI

/// Tasks the user pinned, in a small section above the projects, in their own order:
/// drag to reorder, Unpin from the context menu or a swipe. A pinned task shows only here.
struct PinnedSection<TaskAccessory: View>: View {
    @Environment(AppModel.self) private var model
    @Environment(\.sidebarAllInView) private var isAllInView
    /// The pinned tasks to show: all of them, or those the Needs You filter keeps.
    let sessions: [SessionSummary]
    /// Every pinned task's place in the pin order, filtered out or not.
    let order: [SessionKey: Int]
    let drag: SidebarDragState
    let taskAccessory: (SessionSummary) -> TaskAccessory
    let select: (SessionKey) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: isAllInView ? 0 : DS.Space.xs) {
            if isAllInView {
                // Its rows follow the label as a project's follow its header.
                SidebarSectionLabel("Pinned").padding(.bottom, DS.Space.xxs)
            } else {
                SectionHeader("Pinned")
            }
            ForEach(sessions) { summary in
                let row = SidebarDragState.Item.pinned(summary.id)
                let index = order[summary.id] ?? 0
                SessionRow(
                    summary: summary, indent: .flat, isPinned: model.ordering.isPinned(summary.id),
                    canMoveUp: index > 0, canMoveDown: index < order.count - 1,
                    accessory: taskAccessory(summary)
                ) {
                    select(summary.id)
                }
                .equatable()
                .padding(.leading, model.isCoordinatorChild(summary.id, among: sessions) ? DS.Space.xl : 0)
                .sidebarDraggable(row, title: model.title(for: summary), state: drag)
                .sidebarDropTarget(row, state: drag, onDrop: model.applySidebarDrop)
            }
        }
        .padding(.top, isAllInView ? DS.Space.md : 0)
        .padding(.bottom, isAllInView ? 0 : DS.Space.md)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Pinned")
    }
}

#if DEBUG
#Preview("Pinned section") {
    let app = AppModel.preview()
    DSPreviewPair {
        PinnedSection(
            sessions: app.pinnedSessions, order: [:], drag: SidebarDragState(), taskAccessory: { _ in EmptyView() },
            select: { _ in }
        )
        .frame(width: DS.Size.sidebarWidth)
    }
    .sidebarPreviewEnvironment(app)
}

#Preview("All in view - Pinned section") {
    let app = AppModel.preview()
    DSPreviewPair {
        PinnedSection(
            sessions: app.pinnedSessions, order: [:], drag: SidebarDragState(), taskAccessory: { _ in EmptyView() },
            select: { _ in }
        )
        .environment(\.sidebarAllInView, true)
        .frame(width: DS.Size.sidebarWidth - DS.Sidebar.inset * 2)
    }
    .sidebarPreviewEnvironment(app)
}
#endif
