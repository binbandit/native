import SwiftUI

extension View {
    func projectRenamePresentation() -> some View {
        modifier(ProjectRenamePresentation())
    }
}

/// The same rename dialog serves the File menu and both sidebar menus.
private struct ProjectRenamePresentation: ViewModifier {
    @Environment(AppModel.self) private var model
    @Environment(\.undoManager) private var undoManager

    func body(content: Content) -> some View {
        @Bindable var model = model
        content.alert(
            "Rename Project",
            isPresented: Binding(
                get: { model.renamingProject != nil },
                set: { if !$0 { model.renamingProject = nil } }),
            presenting: model.renamingProject.flatMap(model.projects.project)
        ) { project in
            TextField(project.folderName, text: $model.projectNameDraft)
                .accessibilityLabel("Project name")
            Button("Rename") {
                model.renameProject(project.id, to: model.projectNameDraft, undoManager: undoManager)
            }
            .keyboardShortcut(.defaultAction)
            Button("Cancel", role: .cancel) {}
        } message: { project in
            Text("The folder on disk keeps its name. Clear the name to use “\(project.folderName)”.\n\n\(project.path)")
        }
    }
}

#if DEBUG
#Preview("Project rename - Folder name") {
    let app = AppModel.preview()
    DSPreviewPair {
        Text("Project Home")
            .projectRenamePresentation()
            .onAppear { if let project = app.previewProject() { app.requestRenameProject(project.id) } }
    }
    .sidebarPreviewEnvironment(app)
}

#Preview("Project rename - Custom name") {
    let app = AppModel.preview()
    DSPreviewPair {
        Text("Project Home")
            .projectRenamePresentation()
            .onAppear {
                if let project = app.previewProject() {
                    app.renameProject(project.id, to: "Native at Work")
                    app.requestRenameProject(project.id)
                }
            }
    }
    .sidebarPreviewEnvironment(app)
}
#endif
