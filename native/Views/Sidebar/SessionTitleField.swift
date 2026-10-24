import SwiftUI

/// Edits a session's title in place of its row, keeping the row's glyphs where they were: Return
/// keeps the edit, Escape throws it away, clicking elsewhere keeps it (as in the Finder), and an
/// empty title goes back to the automatic one.
struct SessionTitleField: View {
    @Environment(AppModel.self) private var model
    @AppStorage("sidebar.showAgentIcons") private var showAgentIcons = true
    @Environment(\.sidebarAllInView) private var isAllInView
    @Environment(\.undoManager) private var undoManager
    let summary: SessionSummary
    let status: TaskStatus

    @State private var draft = ""
    @FocusState private var isFocused: Bool

    var body: some View {
        // Mirrors `TaskRow`'s layout so the title doesn't jump when editing starts.
        HStack(alignment: .top, spacing: isAllInView ? DS.Space.md : DS.Space.sm) {
            Group {
                if isAllInView {
                    TaskSignal(status: status, isUnread: model.isUnread(summary.id))
                        .frame(width: DS.Size.rowLeading, height: DS.Size.rowLeading)
                } else if status == .idle || status == .done || status == .cancelled {
                    AgentIcon(agent: summary.agent)
                        .opacity(showAgentIcons ? 1 : 0)
                        .frame(width: DS.Size.rowLeading, height: DS.Size.rowLeading)
                } else {
                    StatusIndicator(status: status)
                }
            }
            .padding(.top, isAllInView ? 0 : DS.Space.xxs)
            .padding(.trailing, isAllInView ? 0 : DS.Space.xxs)
            TextField("Title", text: $draft)
                .textFieldStyle(.plain)
                .font(.dsCalloutBook)
                .foregroundStyle(.dsTextPrimary)
                .focused($isFocused)
                .frame(height: isAllInView ? DS.Sidebar.titleHeight : 20)
                .accessibilityLabel("Task title")
        }
        .padding(.vertical, isAllInView ? DS.Sidebar.rowVertical : DS.Space.md)
        .padding(.leading, isAllInView ? DS.Sidebar.leading : TaskRowIndent.grouped.leading)
        .padding(.trailing, DS.Space.sm)
        .frame(minHeight: isAllInView ? max(DS.Sidebar.rowHeight, DS.Size.minimumHitTarget) : DS.Size.rowMinHeight)
        .background(.dsSelected, in: .rect(cornerRadius: DS.Radius.row, style: .continuous))
        // Outlined so editing reads differently from plain selection.
        .overlay {
            RoundedRectangle(cornerRadius: DS.Radius.row, style: .continuous)
                .strokeBorder(.dsBorderHover)
        }
        .onAppear {
            draft = model.title(for: summary)
        }
        .task {
            // A field can only take focus once it's in the window, after it appears.
            isFocused = true
        }
        .onSubmit(commit)
        .onKeyPress(.escape) {
            model.renaming = nil
            return .handled
        }
        .onChange(of: isFocused) {
            if !isFocused {
                commit()
            }
        }
    }

    private func commit() {
        guard model.renaming == summary.id else { return }
        model.renaming = nil
        let previous = model.title(for: summary)
        guard draft != previous else { return }
        model.rename(summary.id, to: draft, undoManager: undoManager)
    }
}

#if DEBUG
#Preview("Renaming a task") {
    let app = AppModel.preview()
    DSPreviewPair {
        if let summary = SidebarPreviewFixtures.sessions(in: app).first {
            SessionTitleField(summary: summary, status: .working)
                .frame(width: DS.Size.sidebarWidth - DS.Space.lg)
        }
    }
    .sidebarPreviewEnvironment(app)
}
#Preview("All in view - Renaming") {
    let app = AppModel.preview()
    DSPreviewPair {
        if let summary = SidebarPreviewFixtures.sessions(in: app).last {
            SessionTitleField(summary: summary, status: .idle)
                .environment(\.sidebarAllInView, true)
                .frame(width: DS.Window.sidebarMinWidth)
        }
    }
    .sidebarPreviewEnvironment(app)
}
#Preview("All in view - Renaming unread") {
    let app = AppModel.preview()
    let summary = SidebarPreviewFixtures.sessions(in: app).last
    if let summary { app.unread.set(summary.id, unread: true) }
    return DSPreviewPair {
        if let summary {
            SessionTitleField(summary: summary, status: .done)
                .environment(\.sidebarAllInView, true)
                .frame(width: DS.Window.sidebarMinWidth)
        }
    }
    .sidebarPreviewEnvironment(app)
}
#endif
