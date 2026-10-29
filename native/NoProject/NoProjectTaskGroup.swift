import ACP
import SwiftUI
import TaskList

/// The ordinary task row, in a stable group that cannot be archived or treated as a repository.
struct NoProjectTaskGroup<TaskAccessory: View>: View {
    @Environment(AppModel.self) private var model
    let group: SidebarListing.Group
    var isFiltered = false
    var hasNoMatches = false
    var followsPinned = false
    let isExpanded: Binding<Bool>
    let isEarlierExpanded: Binding<Bool>
    let drag: SidebarDragState
    let taskAccessory: (SessionSummary) -> TaskAccessory
    let select: (SessionKey) -> Void

    var body: some View {
        AllInViewProjectGroup(
            name: "No project", isFirst: !followsPinned, isExpanded: isExpanded,
            taskCount: group.current.count + group.earlier.count + model.startingTasks(in: NoProjectLocation.id).count,
            activity: activity, note: hasNoMatches ? "No matching tasks" : nil,
            onNewTask: { Task { await model.newSession(in: NoProjectLocation.id) } }
        ) {
            Button("New Task") { Task { await model.newSession(in: NoProjectLocation.id) } }
        } content: {
            ForEach(model.problems.list(for: NoProjectLocation.id)) { ProjectProblemRow(problem: $0) }
            ForEach(model.startingTasks(in: NoProjectLocation.id)) { StartingTaskRow(task: $0) }
            rows(group.current)
            if !isFiltered, group.current.isEmpty, group.earlier.isEmpty,
                model.startingTasks(in: NoProjectLocation.id).isEmpty,
                model.problems.list(for: NoProjectLocation.id).isEmpty
            {
                Text("Start a task here. A folder is optional.")
                    .font(.dsBody).foregroundStyle(.dsTextTertiary)
                    .padding(.leading, DS.Sidebar.headerLeading)
                    .padding(.vertical, DS.Space.sm)
            }
            if !group.earlier.isEmpty {
                SidebarEarlierDisclosure(count: group.earlier.count, isExpanded: isEarlierExpanded)
                if isEarlierExpanded.wrappedValue { rows(group.earlier) }
            }
        }
    }

    private var activity: ProjectActivity {
        guard !isExpanded.wrappedValue else { return ProjectActivity() }
        var value = ProjectActivity(working: model.startingTasks(in: NoProjectLocation.id).count)
        for task in model.sessions(in: NoProjectLocation.id) {
            switch TaskFacts.Activity(model.session(task.id)) {
            case .needsYou: value.needsYou += 1
            case .running: value.working += 1
            case .failed, .done, .idle: break
            }
        }
        return value
    }

    private func rows(_ tasks: [SessionSummary]) -> some View {
        ForEach(tasks) { summary in
            let index = group.all.firstIndex { $0.id == summary.id } ?? 0
            let item = SidebarDragState.Item.session(summary.id, in: NoProjectLocation.id)
            SessionRow(
                summary: summary, canMoveUp: index > 0, canMoveDown: index < group.all.count - 1,
                accessory: taskAccessory(summary)
            ) { select(summary.id) }
            .equatable()
            .sidebarDraggable(item, title: model.title(for: summary), state: drag)
            .sidebarDropTarget(item, state: drag, onDrop: model.applySidebarDrop)
        }
    }
}

#if DEBUG
#Preview("No project - Empty") {
    let app = AppModel.preview(.empty)
    DSPreviewPair {
        NoProjectTaskGroup(
            group: SidebarListing.Group(project: NoProjectLocation.group, all: [], current: []),
            isExpanded: .constant(true), isEarlierExpanded: .constant(false), drag: SidebarDragState(),
            taskAccessory: { _ in EmptyView() }, select: { _ in }
        )
        .frame(width: DS.Window.sidebarMinWidth)
    }.sidebarPreviewEnvironment(app)
}

#Preview("No project - No matching tasks") {
    let app = AppModel.preview(.empty)
    DSPreviewPair {
        NoProjectTaskGroup(
            group: SidebarListing.Group(project: NoProjectLocation.group, all: [], current: []),
            isFiltered: true, hasNoMatches: true,
            isExpanded: .constant(false), isEarlierExpanded: .constant(false), drag: SidebarDragState(),
            taskAccessory: { _ in EmptyView() }, select: { _ in }
        )
        .frame(width: DS.Window.sidebarMinWidth)
    }.sidebarPreviewEnvironment(app)
}

#Preview("No project - Task row") {
    let app = AppModel.preview()
    let agent = app.agents.first?.agent
    return DSPreviewPair {
        if let agent {
            let summary = SessionSummary(
                project: NoProjectLocation.id, agent: agent,
                info: SessionInfo(sessionId: SessionID("preview"), cwd: "/fixture", title: "Draft a release checklist"))
            NoProjectTaskGroup(
                group: SidebarListing.Group(project: NoProjectLocation.group, all: [summary], current: [summary]),
                isExpanded: .constant(true), isEarlierExpanded: .constant(false), drag: SidebarDragState(),
                taskAccessory: { _ in EmptyView() }, select: { _ in }
            )
            .frame(width: DS.Window.sidebarMinWidth)
        }
    }.sidebarPreviewEnvironment(app)
}
#endif
