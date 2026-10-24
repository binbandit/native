import SwiftUI

struct TaskAttentionToolbarButton: View {
    var maxWidth = DS.Peek.width
    var maxBodyHeight = DS.Peek.maxBodyHeight
    @Environment(AppModel.self) private var model
    @Environment(SettingsPresentation.self) private var settings

    private var items: [TaskAttentionItem] { model.tasksNeedingAttention }

    var body: some View {
        Button {
            model.showTasksNeedingAttention()
        } label: {
            HStack(spacing: DS.Space.sm) {
                TaskSignal(
                    status: .needsInput, placement: .toolbarCount,
                    attentionSince: items.compactMap { $0.ask?.since }.max())
                Text("\(items.count)").font(DS.Sidebar.clockFont).foregroundStyle(.dsAttention)
            }
            .padding(.leading, DS.Sidebar.attentionCountLeading)
            .padding(.trailing, DS.Sidebar.attentionCountTrailing)
            .frame(height: DS.Sidebar.attentionCountHeight)
            .background(.dsSelected, in: .rect(cornerRadius: DS.Sidebar.attentionCountRadius))
            .contentShape(.rect)
            .dsHitTarget(DS.Size.toolbarButton)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(items.count) \(items.count == 1 ? "task needs" : "tasks need") you")
        .accessibilityIdentifier("sidebar-attention")
        .help("Tasks Needing You")
        .popover(
            isPresented: presentation,
            arrowEdge: .bottom
        ) {
            attentionPopover
                .environment(model)
                .presentationBackground(Color.dsOverlay)
                .presentationCompactAdaptation(.popover)
        }
        .focusedSceneValue(\.taskAttentionList, presentation)
        .onChange(of: items.isEmpty) { _, empty in
            if empty { model.closeTasksNeedingAttention() }
        }
        .onDisappear { model.closeTasksNeedingAttention() }
    }

    private var presentation: Binding<Bool> {
        Binding(
            get: { model.taskPeek.showsAttentionList },
            set: {
                if $0 { model.showTasksNeedingAttention() } else { model.closeTasksNeedingAttention() }
            })
    }

    @ViewBuilder private var attentionPopover: some View {
        if let request = model.taskPeek.request {
            TaskPeekView(request: request, maxBodyHeight: min(DS.Peek.maxBodyHeight, maxBodyHeight)) { key in
                settings.close()
                model.openPeekedTask(key)
            }
            .frame(width: min(DS.Peek.width, maxWidth))
            .id(request.id)
        } else {
            TaskAttentionList(maxHeight: min(DS.Sidebar.attentionMaximumHeight, maxBodyHeight))
                .frame(width: min(DS.Sidebar.attentionWidth, maxWidth))
        }
    }
}

#if DEBUG
#Preview("Collapsed signal - Needs you") {
    let app = SidebarDesignFixture.makeApp("busy")
    DSPreviewPair { TaskAttentionToolbarButton() }
        .environment(app).environment(SettingsPresentation())
}
#Preview("Collapsed signal - Nothing needs you") {
    let app = AppModel.preview(.empty)
    DSPreviewPair {
        if !app.tasksNeedingAttention.isEmpty { TaskAttentionToolbarButton() }
    }
    .environment(app).environment(SettingsPresentation())
}
#endif

extension FocusedValues {
    @Entry var taskAttentionList: Binding<Bool>?
}
