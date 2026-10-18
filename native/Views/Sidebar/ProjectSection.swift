import SwiftUI

/// One project and its sessions (the reference app's repository group): the header collapses it, "+" starts
/// a session in it, and its menu (also its context menu) reveals it, changes its icon, archives or
/// deletes it. The header drags to reorder projects; sessions drag to reorder within the project,
/// by mouse or by touch.
struct ProjectSection<TaskAccessory: View>: View {
    @Environment(AppModel.self) private var model
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
        let problems = model.problems(in: project.id)
        ProjectGroup(
            name: project.name,
            icon: iconStore.icon(for: project),
            isExpanded: isExpanded,
            taskCount: sessions.count,
            onNewTask: { Task { await model.newSession(in: project.id) } }
        ) {
            ProjectMenu(
                project: project, position: position, isPickingIcon: $isPickingIcon,
                isConfirmingDelete: $isConfirmingDelete)
        } content: {
            // Work Native did on its own for the project that failed, above the list it may have left stale.
            if !isFiltered {
                ForEach(problems) { problem in
                    ProjectProblemRow(problem: problem)
                }
            }
            ForEach(sessions) { summary in
                let row = SidebarDragState.Item.session(summary.id, in: project.id)
                let index = order[summary.id] ?? 0
                SessionRow(
                    summary: summary, canMoveUp: index > 0, canMoveDown: index < order.count - 1,
                    accessory: taskAccessory(summary)
                ) {
                    select(summary.id)
                }
                .sidebarDraggable(row, title: model.title(for: summary), state: drag)
                .sidebarDropTarget(row, state: drag, isActive: drag.dragged.isSession, onDrop: model.applySidebarDrop)
            }
            // A project whose listing failed isn't known to be empty; its problem row says so.
            if sessions.isEmpty, !isFiltered, !problems.contains(where: \.isListing) {
                ProjectEmptyRow(project: project)
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
            Button("New Session") { Task { await model.newSession(in: project.id) } }
            Button("Move Up") { model.move(.project(project.id), .up) }
            Button("Move Down") { model.move(.project(project.id), .down) }
            Button("Archive") { model.archiveProject(project.id, undoManager: undoManager) }
            Button("Delete") { isConfirmingDelete = true }
        }
    }
}

/// A project's actions, from its "…" button and its context menu (the reference app's repository menu).
private struct ProjectMenu: View {
    @Environment(AppModel.self) private var model
    @Environment(\.undoManager) private var undoManager
    @Environment(\.displayScale) private var displayScale
    @Environment(\.colorScheme) private var colorScheme
    let project: Project
    let position: (index: Int, count: Int)
    @Binding var isPickingIcon: Bool
    @Binding var isConfirmingDelete: Bool

    var body: some View {
        Button("New Session") {
            Task { await model.newSession(in: project.id) }
        }
        .disabled(!model.canCreateSession(in: project.id))
        Menu("New Session With") {
            ForEach(model.agents, id: \.agent.id) { runtime in
                Button {
                    Task { await model.newSession(in: project.id, with: runtime.agent.id) }
                } label: {
                    Label {
                        Text(runtime.agent.displayName)
                    } icon: {
                        AgentIconStore.shared.image(
                            for: runtime.agent, size: DS.Size.rowLeading, scale: displayScale, colorScheme: colorScheme)
                    }
                }
                .disabled(!model.canCreateSession(in: project.id, with: runtime.agent.id))
            }

            if !model.agentsToAdd.isEmpty {
                Divider()
                Button("Add Agent…", systemImage: "plus") { model.isAddingAgent = true }
            }
        }
        // Menus only show item icons when the content asks for them.
        .labelStyle(.titleAndIcon)
        Button("Show Project Home") {
            model.focusProject(project.id)
        }
        Divider()
        Button("Change Icon…") {
            isPickingIcon = true
        }
        Menu("Open In") {
            OpenInMenuContent(location: OpenInLocation(folder: project.url, host: project.host), model: .shared)
        }
        if PlatformFileBrowser.canReveal {
            Button("Show in Finder") {
                PlatformFileBrowser.reveal(project.url)
            }
        }
        Button("Copy Path") {
            DSPasteboard.copy(project.path)
        }
        Divider()
        Button("Move Up") { model.move(.project(project.id), .up) }
            .disabled(position.index == 0)
        Button("Move Down") { model.move(.project(project.id), .down) }
            .disabled(position.index >= position.count - 1)
        Divider()
        Button("Archive Project") {
            model.archiveProject(project.id, undoManager: undoManager)
        }
        Button("Delete Project…", role: .destructive) {
            isConfirmingDelete = true
        }
    }
}

/// What an expanded project with no sessions shows: the one action that fills it, or why it can't
/// happen yet.
private struct ProjectEmptyRow: View {
    @Environment(AppModel.self) private var model
    let project: Project

    @State private var isHovered = false

    var body: some View {
        if model.canCreateSession(in: project.id) {
            Button {
                Task { await model.newSession(in: project.id) }
            } label: {
                Label("Start a session", systemImage: "plus")
                    .labelStyle(EmptyRowLabelStyle())
                    .foregroundStyle(isHovered ? .dsTextSecondary : .dsTextTertiary)
                    .contentShape(.rect)
            }
            .buttonStyle(SidebarRowButtonStyle())
            .trackHover($isHovered)
            .help("New session in \(project.name)")
        } else {
            // Only reached when no agent is installed: starting agents can already take a session.
            Button {
                model.isAddingAgent = true
            } label: {
                Label("Add an agent to start a session", systemImage: "plus")
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

/// Lines the empty row's glyph up with the status glyphs of task rows.
private struct EmptyRowLabelStyle: LabelStyle {
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
        .padding(.leading, TaskRowIndent.grouped.leading)
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
    fileprivate var isListing: Bool {
        if case .listing = work { true } else { false }
    }
}
