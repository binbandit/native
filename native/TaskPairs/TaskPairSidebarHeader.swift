import ACP
import SwiftUI

/// The heading of a brief's two tasks in the sidebar: the brief's title, over the two agents'
/// rows. Clicking it opens the first task.
struct TaskPairSidebarHeader: View {
    let pair: TaskPair
    let select: (SessionKey) -> Void
    @Environment(AppModel.self) private var model
    @Environment(\.sidebarAllInView) private var isAllInView
    @State private var isHovered = false

    var body: some View {
        Button {
            if let first = pair.tasks.first { select(first) }
        } label: {
            HStack(spacing: isAllInView ? DS.Space.md : DS.Space.sm) {
                Color.clear.frame(width: DS.Size.rowLeading, height: DS.Size.rowLeading)
                DSInlineCodeText(title)
                    .font(.dsCalloutBook)
                    .tracking(DS.Sidebar.titleTracking)
                    .foregroundStyle(.dsTextPrimary)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.leading, isAllInView ? DS.Sidebar.leading : TaskRowIndent.grouped.leading)
            .padding(.trailing, DS.Sidebar.trailing)
            .padding(.vertical, DS.Sidebar.rowVertical)
            .frame(minHeight: max(DS.Sidebar.rowHeight, DS.Size.minimumHitTarget))
            .contentShape(.rect)
        }
        .buttonStyle(SidebarRowButtonStyle())
        .background {
            RoundedRectangle(cornerRadius: DS.Radius.row, style: .continuous).fill(isHovered ? .dsHover : .clear)
        }
        .trackHover($isHovered)
        .help("Two agents were given this task. Open one to compare and keep a version.")
        .accessibilityLabel(DSInlineCode.plain(title))
        .accessibilityValue("Two versions, by \(pair.tasks.map(model.taskPairAgentName).joined(separator: " and "))")
    }

    /// The first task's title, which both tasks share until each is titled on its own.
    private var title: String {
        guard let first = pair.tasks.first else { return "New Task" }
        if let starting = model.startingTask(first) {
            let line = starting.draft.split(separator: "\n", omittingEmptySubsequences: true).first
            return line.map { $0.trimmingCharacters(in: .whitespaces) }.flatMap { $0.isEmpty ? nil : $0 } ?? "New Task"
        }
        return model.titleOfSession(first)
    }
}

#if DEBUG
#Preview("Pair - Sidebar group") {
    DSPreviewPair {
        let fixtures = TaskPairPreviewFixtures.self
        let app = fixtures.app()
        VStack(spacing: 0) {
            TaskPairSidebarHeader(pair: fixtures.pair(in: app)) { _ in }
            AllInViewTaskRow(title: "Codex", status: .done, isUnread: true, branchName: "binbandit/offline-time-pill-2")
            {}
            .padding(.leading, DS.TaskPair.memberIndent)
            AllInViewTaskRow(
                title: "Claude Code", status: .idle, isSelected: true, branchName: "binbandit/offline-time-pill"
            ) {}
            .padding(.leading, DS.TaskPair.memberIndent)
            AllInViewTaskRow(title: "Queue follow-ups while a turn runs", status: .working) {}
        }
        .environment(app)
        .environment(\.sidebarAllInView, true)
        .frame(width: DS.Size.sidebarWidth - DS.Sidebar.inset * 2)
    }
}
#endif
