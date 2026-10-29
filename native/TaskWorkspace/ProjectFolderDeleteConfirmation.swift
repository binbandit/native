import SwiftUI

extension View {
    func projectFolderDeletePresentation() -> some View {
        modifier(ProjectFolderDeleteConfirmation())
    }
}

private struct ProjectFolderDeleteConfirmation: ViewModifier {
    @Environment(AppModel.self) private var app

    func body(content: Content) -> some View {
        content.confirmationDialog(
            app.projectFolderDeletion?.title ?? "Delete this task?",
            isPresented: Binding(
                get: { app.projectFolderDeletion != nil },
                set: { if !$0 { app.projectFolderDeletion = nil } }
            ), titleVisibility: .visible, presenting: app.projectFolderDeletion
        ) { request in
            Button("Cancel", role: .cancel) { app.projectFolderDeletion = nil }
            Button("Delete", role: .destructive) {
                app.projectFolderDeletion = nil
                request.confirm()
            }
        } message: { _ in
            Text(
                "Conversations are removed from Native. Files in the project folder and its current branch stay as they are."
            )
        }
    }
}

#if DEBUG
#Preview("Delete project folder task - Files stay") {
    DSPreviewPair {
        let app = AppModel.preview(.empty)
        VStack {
            Button("Delete this task") {
                app.projectFolderDeletion = ProjectFolderDeletion(title: "Delete this task?", confirm: {})
            }
            Button("Delete these tasks") {
                app.projectFolderDeletion = ProjectFolderDeletion(title: "Delete these tasks?", confirm: {})
            }
        }
        .projectFolderDeletePresentation()
        .environment(app)
    }
}
#endif
