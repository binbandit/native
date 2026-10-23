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
    @Environment(\.sidebarQuietProjects) private var isQuiet
    @Environment(\.sidebarSelection) private var picking
    @Environment(\.undoManager) private var undoManager
    @Environment(\.projectIconStore) private var injectedIconStore
    let project: Project
    /// The sessions to show: all of them, or those the Needs You filter keeps.
    let sessions: [SessionSummary]
    /// Every session's place in the project's order, filtered out or not.
    let order: [SessionKey: Int]
    /// The project's place among the projects, and how many there are.
    let position: (index: Int, count: Int)
    let isFiltered: Bool
    var allowsFolding = true
    /// The filters leave none of its tasks.
    var hasNoMatches = false
    let isExpanded: Binding<Bool>
    let drag: SidebarDragState
    let taskAccessory: (SessionSummary) -> TaskAccessory
    /// A session row was clicked.
    let select: (SessionKey) -> Void

    @State private var showsAll = false
    @State private var isPickingIcon = false
    @State private var isConfirmingDelete = false

    private var iconStore: ProjectIconStore {
        injectedIconStore ?? .shared
    }

    var body: some View {
        let item = SidebarDragState.Item.project(project.id)
        let problems = model.problems.list(for: project.id)
        let starting = model.startingTasks(in: project.id)
        let visible = visibleSessions
        projectGroup(starting: starting.count) {
            // Work Native did on its own for the project that failed, above the list it may have left stale.
            if !isFiltered {
                ForEach(problems) { problem in
                    ProjectProblemRow(problem: problem)
                }
            }
            ForEach(starting) { task in
                StartingTaskRow(task: task)
            }
            ForEach(visible) { summary in
                let row = SidebarDragState.Item.session(summary.id, in: project.id)
                let index = order[summary.id] ?? 0
                SessionRow(
                    summary: summary, canMoveUp: index > 0, canMoveDown: index < order.count - 1,
                    accessory: taskAccessory(summary)
                ) {
                    select(summary.id)
                }
                .equatable()
                .sidebarDraggable(row, title: model.title(for: summary), state: drag)
                .sidebarDropTarget(row, state: drag, isActive: drag.dragged.isSession, onDrop: model.applySidebarDrop)
            }
            if isQuiet, allowsFolding, !isFiltered, picking?.isActive != true,
                sessions.count > visible.count || showsAll
            {
                SidebarNextDisclosureRow(
                    title: showsAll ? "Show less" : "\(sessions.count - visible.count) more",
                    isExpanded: showsAll
                ) { withAnimation(.dsDisclosure) { showsAll.toggle() } }
            }
            // A project whose folder is gone or whose listing failed isn't known to be empty; its
            // problem row says why.
            if sessions.isEmpty, starting.isEmpty, !isFiltered, !problems.contains(where: \.leavesListUnknown) {
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

    /// Filters and bulk selection expose their full scope. A keyboard or search selection must
    /// remain visible even when it points into the folded tail.
    private var visibleSessions: [SessionSummary] {
        guard isQuiet, allowsFolding, !showsAll, !isFiltered, picking?.isActive != true else { return sessions }
        var keeping = Set<SessionKey>()
        var dates: [SessionKey: Date] = [:]
        for summary in sessions {
            let session = model.session(summary.id)
            let status = TaskStatus(session)
            if status.isActive || status.needsAttention || status == .failed || status == .paused || status == .limited
                || model.isUnread(summary.id)
                || model.removedWorkspaces[summary.id] != nil
            {
                keeping.insert(summary.id)
            }
            dates[summary.id] = session?.lastActivity ?? summary.info.updatedDate
        }
        let visible = TaskListFold.visibleIDs(
            ordered: sessions.map(\.id), keeping: keeping, dates: dates,
            revealing: Set([model.selection, model.renaming].compactMap { $0 }))
        return sessions.filter { visible.contains($0.id) }
    }

    @ViewBuilder private func projectGroup<Content: View>(
        starting: Int, @ViewBuilder content: @escaping () -> Content
    ) -> some View {
        let onNewTask: (() -> Void)? =
            model.missingFolder(of: project.id) == nil
            ? { Task { await model.newSession(in: project.id) } } : nil
        let activity = isExpanded.wrappedValue ? ProjectActivity() : activity(starting: starting)
        if isQuiet {
            SidebarNextProjectGroup(
                name: project.name, isExpanded: isExpanded, taskCount: sessions.count,
                isRefreshing: model.refreshingProjects.contains(project.id), activity: activity,
                note: hasNoMatches ? "No matching tasks" : nil, onNewTask: onNewTask,
                menu: { projectMenu }, content: content)
        } else {
            ProjectGroup(
                name: project.name, icon: iconStore.icon(for: project), isExpanded: isExpanded,
                taskCount: sessions.count, activity: activity,
                isRefreshing: model.refreshingProjects.contains(project.id),
                note: hasNoMatches ? "No matching tasks" : nil,
                onNewTask: onNewTask, menu: { projectMenu }, content: content)
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
    @Environment(\.sidebarQuietProjects) private var isQuiet
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
                        ? "Restart an agent to start a task" : isQuiet ? "Start the first task" : "Start a task",
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
    var body: some View {
        Label {
            Text("Finding tasks…")
        } icon: {
            DotGridLoader(pattern: .settingUp)
                .frame(width: DS.Size.rowLeading * 0.75, height: DS.Size.rowLeading * 0.75)
        }
        .labelStyle(EmptyRowLabelStyle())
        .foregroundStyle(.dsTextTertiary)
        .accessibilityElement(children: .combine)
    }
}

/// Lines the empty row's glyph up with the status glyphs of task rows.
private struct EmptyRowLabelStyle: LabelStyle {
    @Environment(\.sidebarQuietProjects) private var isQuiet

    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: DS.Space.sm) {
            configuration.icon
                .font(.dsCaption)
                .frame(width: DS.Size.rowLeading, height: DS.Size.rowLeading)
            configuration.title
                .font(.dsCalloutBook)
            Spacer(minLength: 0)
        }
        .padding(.vertical, DS.Space.md)
        .padding(.leading, isQuiet ? TaskRowIndent.flat.leading : TaskRowIndent.grouped.leading)
        .padding(.trailing, DS.Space.sm)
        .frame(minHeight: DS.Size.rowMinHeight)
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
#endif
