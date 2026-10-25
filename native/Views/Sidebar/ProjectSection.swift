import ACP
import SwiftUI
import TaskList

/// One project and its sessions: the header collapses it, "+" starts
/// a session in it, and its menu (also its context menu) opens its settings, reveals it, changes its
/// icon, archives or deletes it. The header drags to reorder projects; sessions drag to reorder within the project,
/// by mouse or by touch. Sessions being started come first, and until its first listing a project
/// says it's finding its sessions rather than that it has none. Collapsed, the header says what its
/// tasks are doing.
struct ProjectSection<TaskAccessory: View>: View {
    @Environment(AppModel.self) private var model
    @Environment(\.sidebarAllInView) private var isAllInView
    @Environment(\.undoManager) private var undoManager
    @Environment(\.projectIconStore) private var injectedIconStore
    let project: Project
    /// The sessions to show: all of them, or those the Needs You filter keeps.
    let sessions: [SessionSummary]
    var earlier: [SessionSummary] = []
    var isEarlierExpanded: Binding<Bool> = .constant(false)
    /// Every session's place in the project's order, filtered out or not.
    let order: [SessionKey: Int]
    /// The project's place among the projects, and how many there are.
    let position: (index: Int, count: Int)
    let isFiltered: Bool
    /// The filters leave none of its tasks.
    var hasNoMatches = false
    let isExpanded: Binding<Bool>
    let drag: SidebarDragState
    let taskAccessory: (SessionSummary) -> TaskAccessory
    /// A session row was clicked.
    let select: (SessionKey) -> Void

    @State private var isPickingIcon = false
    @State private var isConfirmingDelete = false

    private var iconStore: ProjectIconStore {
        injectedIconStore ?? .shared
    }

    var body: some View {
        let item = SidebarDragState.Item.project(project.id)
        let problems = model.problems.list(for: project.id)
        let starting = model.startingTasks(in: project.id)
        projectGroup(starting: starting.count) {
            // Work Native did on its own for the project that failed, above the list it may have left stale.
            ForEach(problems.filter { !isFiltered || $0.work == .refresh }) { problem in
                ProjectProblemRow(problem: problem)
            }
            let startingKeys = starting.map(\.id)
            ForEach(starting) { task in
                let placement = model.taskPairPlacement(of: task.id, among: startingKeys)
                if case .first(let pair)? = placement {
                    TaskPairSidebarHeader(pair: pair, select: select)
                }
                StartingTaskRow(task: task, isPairMember: placement != nil)
                    .padding(.leading, placement != nil ? DS.TaskPair.memberIndent : 0)
            }
            taskRows(sessions)
            if !earlier.isEmpty {
                SidebarEarlierDisclosure(count: earlier.count, isExpanded: isEarlierExpanded)
                if isEarlierExpanded.wrappedValue { taskRows(earlier) }
            }
            // A project whose folder is gone or whose listing failed isn't known to be empty; its
            // problem row says why.
            if sessions.isEmpty, earlier.isEmpty, starting.isEmpty, !isFiltered,
                !problems.contains(where: \.leavesListUnknown)
            {
                if model.isFindingSessions(in: project.id) {
                    FindingSessionsRow()
                } else {
                    ProjectEmptyRow(project: project)
                }
            }
        }
        // The icon picker hangs off the project's header, not the middle of its sessions.
        .overlay(alignment: .topLeading) {
            Color.clear
                .frame(width: DS.Size.sidebarWidth / 2, height: DS.Size.controlMD)
                .allowsHitTesting(false)
                .popover(isPresented: $isPickingIcon, arrowEdge: .trailing) {
                    ProjectIconPicker(project: project, store: iconStore)
                        .dsPopoverBackground()
                }
        }
        .sidebarDraggable(item, title: project.name, state: drag)
        .sidebarDropTarget(item, state: drag, onDrop: model.applySidebarDrop)
        .projectDeletionConfirmation(project, isPresented: $isConfirmingDelete)
        .task(id: project.id) { await iconStore.resolve(project) }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(project.name)
        .accessibilityActions {
            Button("New Task") { Task { await model.newSession(in: project.id) } }
            Button("Refresh") { Task { await model.refreshProject(project.id) } }
            Button("Move Up") { model.move(.project(project.id), .up) }
            Button("Move Down") { model.move(.project(project.id), .down) }
            Button("Archive") { model.archiveProject(project.id, undoManager: undoManager) }
            Button("Delete") { isConfirmingDelete = true }
        }
    }

    private func taskRows(_ rows: [SessionSummary]) -> some View {
        let keys = rows.map(\.id)
        return ForEach(rows) { summary in
            let row = SidebarDragState.Item.session(summary.id, in: project.id)
            let index = order[summary.id] ?? 0
            // A brief's two tasks sit under its title, each named by its agent.
            let placement = model.taskPairPlacement(of: summary.id, among: keys)
            if case .first(let pair)? = placement {
                TaskPairSidebarHeader(pair: pair, select: select)
            }
            SessionRow(
                summary: summary, isPairMember: placement != nil, canMoveUp: index > 0,
                canMoveDown: index < order.count - 1, accessory: taskAccessory(summary)
            ) {
                select(summary.id)
            }
            .equatable()
            .padding(
                .leading,
                model.isCoordinatorChild(summary.id, among: sessions + earlier)
                    ? DS.Space.xl : placement != nil ? DS.TaskPair.memberIndent : 0
            )
            .sidebarDraggable(row, title: model.title(for: summary), state: drag)
            .sidebarDropTarget(row, state: drag, isActive: drag.dragged.isSession, onDrop: model.applySidebarDrop)
        }
    }

    @ViewBuilder private func projectGroup<Content: View>(
        starting: Int, @ViewBuilder content: @escaping () -> Content
    ) -> some View {
        let onNewTask: (() -> Void)? =
            model.missingFolder(of: project.id) == nil
            ? { Task { await model.newSession(in: project.id) } } : nil
        let activity = isExpanded.wrappedValue ? ProjectActivity() : activity(starting: starting)
        if isAllInView {
            AllInViewProjectGroup(
                name: project.name, isFirst: position.index == 0, isExpanded: isExpanded,
                taskCount: sessions.count + earlier.count,
                isRefreshing: model.refreshingProjects.contains(project.id), activity: activity,
                note: hasNoMatches ? "No matching tasks" : nil, onNewTask: onNewTask,
                menu: { projectMenu }, content: content)
        } else {
            ProjectGroup(
                name: project.name, icon: iconStore.icon(for: project), isExpanded: isExpanded,
                taskCount: sessions.count + earlier.count, activity: activity,
                isRefreshing: model.refreshingProjects.contains(project.id),
                note: hasNoMatches ? "No matching tasks" : nil,
                onNewTask: onNewTask, menu: { projectMenu }, content: content)
        }
        // A refresh requested from a collapsed or filtered project still needs a visible recovery.
        if !isExpanded.wrappedValue {
            ForEach(model.problems.list(for: project.id).filter { $0.work == .refresh }) { problem in
                ProjectProblemRow(problem: problem)
            }
        }
    }

    private var projectMenu: some View {
        ProjectMenu(
            project: project, position: position, isPickingIcon: $isPickingIcon,
            isConfirmingDelete: $isConfirmingDelete)
    }

    /// How many of the project's tasks need the user and how many are working, every task counted
    /// whatever the filter shows; sessions being started count as working.
    private func activity(starting: Int) -> ProjectActivity {
        var activity = ProjectActivity(working: starting)
        for summary in model.sessions(in: project.id) {
            switch TaskFacts.Activity(model.session(summary.id)) {
            case .needsYou: activity.needsYou += 1
            case .running: activity.working += 1
            case .failed, .done, .idle: break
            }
        }
        return activity
    }
}

/// What an expanded project with no sessions shows: the one action that fills it, or why it can't
/// happen yet.
private struct ProjectEmptyRow: View {
    @Environment(\.sidebarAllInView) private var isAllInView
    @Environment(AppModel.self) private var model
    let project: Project

    @State private var isHovered = false

    var body: some View {
        if model.canCreateSession(in: project.id) || model.agentStartupFailure != nil {
            Button {
                Task { await model.newSession(in: project.id) }
            } label: {
                Label(
                    model.agentStartupFailure != nil
                        ? "Restart an agent to start a task" : isAllInView ? "Start the first task" : "Start a task",
                    systemImage: "plus"
                )
                .labelStyle(EmptyRowLabelStyle())
                .foregroundStyle(isHovered ? .dsTextSecondary : .dsTextTertiary)
                .contentShape(.rect)
            }
            .buttonStyle(SidebarRowButtonStyle())
            .trackHover($isHovered)
            .help("New task in \(project.name)")
        } else {
            // Only reached when no agent is installed: starting agents can already take a session.
            Button {
                model.isAddingAgent = true
            } label: {
                Label("Add an agent to start a task", systemImage: "plus")
                    .labelStyle(EmptyRowLabelStyle())
                    .foregroundStyle(isHovered ? .dsTextSecondary : .dsTextTertiary)
                    .contentShape(.rect)
            }
            .buttonStyle(SidebarRowButtonStyle())
            .trackHover($isHovered)
            .help("Install an agent to work in \(project.name)")
        }
    }
}

/// A project whose sessions haven't been listed yet: the loader and what's happening, so a project
/// just added doesn't look empty while its agents list it.
private struct FindingSessionsRow: View {
    @Environment(\.sidebarAllInView) private var isAllInView
    var body: some View {
        Label {
            Text("Finding tasks…")
        } icon: {
            if isAllInView {
                TaskSignal(status: .starting)
            } else {
                DotGridLoader(pattern: .settingUp)
                    .frame(width: DS.Size.rowLeading * 0.75, height: DS.Size.rowLeading * 0.75)
            }
        }
        .labelStyle(EmptyRowLabelStyle())
        .foregroundStyle(.dsTextTertiary)
        .accessibilityElement(children: .combine)
    }
}

/// Lines the empty row's glyph up with the status glyphs of task rows.
private struct EmptyRowLabelStyle: LabelStyle {
    @Environment(\.sidebarAllInView) private var isAllInView

    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: isAllInView ? DS.Space.md : DS.Space.sm) {
            configuration.icon
                .font(.dsCaption)
                .frame(width: DS.Size.rowLeading, height: DS.Size.rowLeading)
            configuration.title
                .font(isAllInView ? .dsBody : .dsCalloutBook)
            Spacer(minLength: 0)
        }
        .padding(.vertical, isAllInView ? DS.Sidebar.rowVertical : DS.Space.md)
        .padding(.leading, isAllInView ? DS.Sidebar.leading : TaskRowIndent.grouped.leading)
        .padding(.trailing, DS.Space.sm)
        .frame(minHeight: isAllInView ? max(DS.Sidebar.rowHeight, DS.Size.minimumHitTarget) : DS.Size.rowMinHeight)
    }
}

extension View {
    /// Asks before deleting a project, saying exactly what goes: Native's record of it and the
    /// workspaces Native made for its tasks, never the folder itself.
    func projectDeletionConfirmation(_ project: Project, isPresented: Binding<Bool>) -> some View {
        modifier(ProjectDeletionConfirmation(project: project, isPresented: isPresented))
    }
}

private struct ProjectDeletionConfirmation: ViewModifier {
    @Environment(AppModel.self) private var model
    @Environment(\.undoManager) private var undoManager
    let project: Project
    @Binding var isPresented: Bool

    func body(content: Content) -> some View {
        content.confirmationDialog("Delete “\(project.name)” from Native?", isPresented: $isPresented) {
            Button("Delete Project", role: .destructive) {
                model.deleteProject(project.id, undoManager: undoManager)
            }
        } message: {
            Text(
                "\(project.path) won't be touched. Native forgets the project and removes the task workspaces it created for it. You can undo for a few seconds. To hide it instead, archive it."
            )
        }
    }
}

extension Optional where Wrapped == SidebarDragState.Item {
    fileprivate var isSession: Bool {
        if case .session = self { true } else { false }
    }
}

extension ProjectProblem {
    fileprivate var leavesListUnknown: Bool {
        switch work {
        case .folder, .listing: true
        case .refresh, .agentCopyDeletion, .workspaceDeletion, .workspaceArchive, .workspaceRestore: false
        }
    }
}

#if DEBUG
#Preview("Project section") {
    let app = AppModel.preview()
    let sessions = SidebarPreviewFixtures.sessions(in: app)
    DSPreviewPair {
        if let project = app.previewProject(0) {
            VStack(alignment: .leading, spacing: DS.Space.xxs) {
                ProjectSection(
                    project: project, sessions: sessions, order: [:], position: (0, 3), isFiltered: false,
                    isExpanded: .constant(true), drag: SidebarDragState(), taskAccessory: { _ in EmptyView() },
                    select: { _ in })
                // Collapsed, the header says what its tasks are doing.
                ProjectSection(
                    project: project, sessions: sessions, order: [:], position: (0, 3), isFiltered: false,
                    isExpanded: .constant(false), drag: SidebarDragState(), taskAccessory: { _ in EmptyView() },
                    select: { _ in })
            }
            .frame(width: DS.Size.sidebarWidth - DS.Space.lg)
        }
    }
    .sidebarPreviewEnvironment(app)
}

#Preview("Project section - No matches") {
    let app = AppModel.preview()
    DSPreviewPair {
        if let project = app.previewProject(1) {
            ProjectSection(
                project: project, sessions: [], order: [:], position: (1, 3), isFiltered: true, hasNoMatches: true,
                isExpanded: .constant(false), drag: SidebarDragState(), taskAccessory: { _ in EmptyView() },
                select: { _ in }
            )
            .frame(width: DS.Size.sidebarWidth - DS.Space.lg)
        }
    }
    .sidebarPreviewEnvironment(app)
}
#Preview("Project section - Coordinator assignments") {
    let app = CoordinatorTaskPreviewFixtures.app()
    DSPreviewPair {
        if let project = app.previewProject(0) {
            ProjectSection(
                project: project,
                sessions: app.sessions(in: project.id).sorted { $0.id.id.rawValue < $1.id.id.rawValue },
                order: [:], position: (0, 1), isFiltered: false, isExpanded: .constant(true),
                drag: SidebarDragState(), taskAccessory: { _ in EmptyView() }, select: { _ in }
            )
            .frame(width: DS.Size.sidebarWidth)
        }
    }.sidebarPreviewEnvironment(app)
}
#endif
