import SwiftUI

/// A project's actions, from its "…" button and its context menu.
struct ProjectMenu: View {
    @Environment(AppModel.self) private var model
    @Environment(SettingsPresentation.self) private var settings
    @Environment(\.undoManager) private var undoManager
    @Environment(\.displayScale) private var displayScale
    @Environment(\.colorScheme) private var colorScheme
    let project: Project
    let position: (index: Int, count: Int)
    @Binding var isPickingIcon: Bool
    @Binding var isConfirmingDelete: Bool

    var body: some View {
        Button("New Task") {
            Task { await model.newSession(in: project.id) }
        }
        .disabled(!model.canCreateSession(in: project.id))
        Menu("New Task With") {
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
        Button("Refresh", systemImage: "arrow.clockwise") {
            Task { await model.refreshProject(project.id) }
        }
        .disabled(model.refreshingProjects.contains(project.id))
        ProjectActionsProjectMenu(project: project)
        Divider()
        Button("Project Settings…") {
            settings.open(.project(project.id))
        }
        Button("Rename Project…", systemImage: "pencil") {
            model.requestRenameProject(project.id)
        }
        .disabled(project.host != .local)
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
        GitCleanupMenuItem(project: project)
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
#if DEBUG
#Preview("Project menu") {
    @Previewable @State var isPickingIcon = false
    @Previewable @State var isConfirmingDelete = false
    let app = AppModel.preview()
    DSPreviewPair {
        if let project = app.previewProject() {
            Menu("Project Options") {
                ProjectMenu(
                    project: project, position: (0, 3), isPickingIcon: $isPickingIcon,
                    isConfirmingDelete: $isConfirmingDelete)
            }
        }
    }
    .sidebarPreviewEnvironment(app)
}
#endif
