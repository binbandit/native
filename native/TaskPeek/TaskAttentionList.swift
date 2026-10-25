import SwiftUI

/// The same speaking rows as All in view, with asks first and failures after a quiet rule.
struct TaskAttentionList: View {
    var maxHeight = DS.Sidebar.attentionMaximumHeight
    @Environment(AppModel.self) private var model
    @State private var highlighted: SessionKey?
    @FocusState private var isFocused: Bool

    private var items: [TaskAttentionItem] { model.tasksNeedingAttention }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: DS.Space.md) {
                Text("Needs you").font(.dsCalloutSemibold).foregroundStyle(.dsTextPrimary)
                Text("\(items.count)").font(DS.Sidebar.clockFont).foregroundStyle(.dsTextTertiary)
                Spacer(minLength: DS.Space.md)
                Text("Space to peek").font(.dsCaption).foregroundStyle(.dsTextTertiary)
            }
            .padding(.horizontal, DS.Sidebar.trailing)
            .padding(.top, DS.Sidebar.attentionHeaderTop)
            .padding(.bottom, DS.Sidebar.attentionHeaderBottom)
            ScrollViewReader { proxy in
                HeightCappedScrollView(maxHeight: maxHeight) {
                    VStack(spacing: 0) {
                        ForEach(items) { item in
                            if item.id == items.first(where: { $0.ask == nil })?.id,
                                items.contains(where: { $0.ask != nil })
                            {
                                SeparatorLine()
                                    .padding(.horizontal, DS.Sidebar.trailing)
                                    .padding(.vertical, DS.Space.sm)
                            }
                            row(item).id(item.id)
                        }
                    }
                }
                .onChange(of: highlighted) { _, key in
                    if let key { proxy.scrollTo(key) }
                }
            }
        }
        .padding(DS.Sidebar.inset)
        .background(.dsOverlay)
        .accessibilityIdentifier("tasks-needing-you")
        .focusable().focused($isFocused).focusEffectDisabled()
        .onAppear {
            highlighted = items.first?.id
            isFocused = true
        }
        .onChange(of: items.map(\.id)) { _, keys in
            if !keys.contains(where: { $0 == highlighted }) { highlighted = keys.first }
        }
        .onKeyPress(.downArrow) {
            move(1); return .handled
        }
        .onKeyPress(.upArrow) {
            move(-1); return .handled
        }
        .onKeyPress(.space) {
            peekHighlighted(); return .handled
        }
        .onKeyPress(.return) {
            peekHighlighted(); return .handled
        }
        .onKeyPress(.escape) {
            model.closeTasksNeedingAttention(); return .handled
        }
    }

    private func row(_ item: TaskAttentionItem) -> some View {
        AllInViewTaskRow(
            title: model.title(for: item.summary), status: TaskStatus(model.session(item.id)),
            isSelected: highlighted == item.id,
            ask: item.ask?.sentence ?? "The task stopped unexpectedly. Peek to continue.",
            attentionSince: item.ask?.since,
            answersShortcut: item.ask?.id == model.oldestTaskAsk?.id && item.ask != nil,
            askShortcut: CommandRegistry.shared.keyboardShortcut(for: .taskAnswerOldestAsk),
            projectName: model.projects.project(item.summary.project)?.name,
            action: { model.peekTask(item.id, ask: item.ask) }
        )
        .accessibilityHint("Opens Peek without leaving the current task.")
    }

    private func move(_ offset: Int) {
        guard !items.isEmpty else { return }
        let current = items.firstIndex { $0.id == highlighted } ?? 0
        highlighted = items[min(max(current + offset, 0), items.count - 1)].id
    }

    private func peekHighlighted() {
        guard let item = items.first(where: { $0.id == highlighted }) else { return }
        model.peekTask(item.id, ask: item.ask)
    }
}

#if DEBUG
#Preview("Needs you - Asks and failure") {
    let app = SidebarDesignFixture.makeApp("busy")
    DSPreviewPair { TaskAttentionList().frame(width: DS.Sidebar.attentionWidth) }.environment(app)
}
#Preview("Needs you - Long plan, narrow") {
    let app = SidebarDesignFixture.makeApp("plan")
    DSPreviewPair { TaskAttentionList().frame(width: DS.Size.sidebarWidth) }.environment(app)
}
#Preview("Needs you - One ask") {
    let app = SidebarDesignFixture.makeApp("collapsed-single")
    DSPreviewPair { TaskAttentionList().frame(width: DS.Sidebar.attentionWidth) }.environment(app)
}
#Preview("Needs you - Failure only") {
    let app = SidebarDesignFixture.makeApp("collapsed-failure")
    DSPreviewPair { TaskAttentionList().frame(width: DS.Sidebar.attentionWidth) }.environment(app)
}
#Preview("Needs you - Long list") {
    let app = SidebarDesignFixture.makeApp("collapsed-many")
    DSPreviewPair { TaskAttentionList().frame(width: DS.Sidebar.attentionWidth) }.environment(app)
}
#endif
