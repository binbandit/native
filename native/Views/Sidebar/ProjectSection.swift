import AppKit
import SwiftUI

/// One project and its sessions (the reference app's repository group): the header collapses it, "+" starts
/// a session in it, and its menu reveals it, opens its home or removes it. The header drags to
/// reorder projects; sessions drag to reorder within the project.
struct ProjectSection<TaskAccessory: View>: View {
    @Environment(AppModel.self) private var model
    let project: Project
    let isExpanded: Binding<Bool>
    let drag: SidebarDragState
    let taskAccessory: (SessionSummary) -> TaskAccessory
    /// A session row was clicked.
    let select: (SessionKey) -> Void

    var body: some View {
        let sessions = model.sessions(in: project.id)
        let item = SidebarDragState.Item.project(project.id)
        ProjectGroup(
            name: project.name,
            icon: .initial,
            isExpanded: isExpanded,
            taskCount: sessions.count,
            onNewTask: { Task { await model.newSession(in: project.id) } }
        ) {
            ProjectMenu(project: project)
        } content: {
            ForEach(sessions) { summary in
                let row = SidebarDragState.Item.session(summary.id, in: project.id)
                SessionRow(summary: summary, accessory: taskAccessory(summary)) {
                    select(summary.id)
                }
                .sidebarDraggable(row, title: model.title(for: summary), state: drag)
                .sidebarDropTarget(row, state: drag, isActive: drag.dragged.isSession, onDrop: model.applySidebarDrop)
            }
            if sessions.isEmpty {
                ProjectEmptyRow(project: project)
            }
        }
        .sidebarDraggable(item, title: project.name, state: drag)
        .sidebarDropTarget(item, state: drag, onDrop: model.applySidebarDrop)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(project.name)
        .accessibilityActions {
            Button("New Session") { Task { await model.newSession(in: project.id) } }
            Button("Move Up") { model.move(.project(project.id), .up) }
            Button("Move Down") { model.move(.project(project.id), .down) }
        }
    }
}

/// A project's actions, from its "…" button and its context menu (the reference app's repository menu).
private struct ProjectMenu: View {
    @Environment(AppModel.self) private var model
    @Environment(\.undoManager) private var undoManager
    let project: Project

    var body: some View {
        Button("New Session") {
            Task { await model.newSession(in: project.id) }
        }
        .disabled(!model.canCreateSession(in: project.id))
        Menu("New Session With") {
            ForEach(model.agents, id: \.agent.id) { runtime in
                Button(runtime.agent.displayName, systemImage: runtime.agent.symbolName) {
                    Task { await model.newSession(in: project.id, with: runtime.agent.id) }
                }
                .disabled(!model.canCreateSession(in: project.id, with: runtime.agent.id))
            }
        }
        Button("Show Project Home") {
            model.focusProject(project.id)
        }
        Divider()
        Button("Show in Finder") {
            NSWorkspace.shared.activateFileViewerSelecting([project.url])
        }
        Button("Copy Path") {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(project.path, forType: .string)
        }
        Divider()
        Button("Move Up") { model.move(.project(project.id), .up) }
            .disabled(!model.canMove(.project(project.id), .up))
        Button("Move Down") { model.move(.project(project.id), .down) }
            .disabled(!model.canMove(.project(project.id), .down))
        Divider()
        // Only the sidebar entry goes; the folder and the agents' history stay, and ⌘Z brings it back.
        Button("Remove Project", role: .destructive, action: remove)
    }

    private func remove() {
        guard let index = model.projects.all.firstIndex(of: project) else { return }
        model.removeProject(project.id)
        undoManager?.registerUndo(withTarget: model) { [project] model in
            Task {
                await model.addProject(project.url)
                if let restored = model.projects.all.lastIndex(where: { $0.url == project.url }), restored != index {
                    model.moveProjects(fromOffsets: [restored], toOffset: index)
                }
            }
        }
        undoManager?.setActionName("Remove Project")
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
            Text(
                model.agents.contains { $0.status == .starting }
                    ? "No sessions yet. Agents are starting…" : "No sessions yet. Set up an agent below to start one."
            )
            .font(.dsBody)
            .foregroundStyle(.dsTextTertiary)
            .padding(.leading, TaskRowIndent.grouped.leading)
            .padding(.vertical, DS.Space.sm)
            .frame(maxWidth: .infinity, alignment: .leading)
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
    }
}

private extension Optional where Wrapped == SidebarDragState.Item {
    var isSession: Bool {
        if case .session = self { true } else { false }
    }
}
