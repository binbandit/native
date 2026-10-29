import SwiftUI

struct ProjectFolderDeleteConfirmation: View {
    let title: String
    let cancel: () -> Void
    let confirm: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.lg) {
            Text(title).font(.dsHeadline).foregroundStyle(.dsTextPrimary)
            Text(
                "The conversation is removed from Native. Files in the project folder and its current branch stay as they are."
            )
            .font(.dsBody).foregroundStyle(.dsTextSecondary)
            .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: DS.Space.md) {
                Spacer(minLength: 0)
                Button("Cancel", action: cancel).buttonStyle(.ds(.secondary, size: .medium))
                    .keyboardShortcut(.cancelAction)
                Button("Delete Task", role: .destructive, action: confirm)
                    .buttonStyle(.ds(.destructive, size: .medium))
            }
        }
        .padding(DS.Space.xxl)
        .frame(idealWidth: DS.TaskWorkspace.sheetWidth, maxWidth: DS.TaskWorkspace.sheetWidth)
        .background(.dsBackground)
    }
}

extension View {
    func projectFolderDeletePresentation() -> some View {
        modifier(ProjectFolderDeleteModifier())
    }
}

private struct ProjectFolderDeleteModifier: ViewModifier {
    @Environment(AppModel.self) private var app

    func body(content: Content) -> some View {
        content.sheet(
            isPresented: Binding(
                get: { app.projectFolderDeletion != nil },
                set: { if !$0 { app.projectFolderDeletion = nil } }
            )
        ) {
            if let request = app.projectFolderDeletion {
                ProjectFolderDeleteConfirmation(
                    title: request.title,
                    cancel: { app.projectFolderDeletion = nil },
                    confirm: {
                        app.projectFolderDeletion = nil
                        request.confirm()
                    })
            }
        }
    }
}

#if DEBUG
#Preview("Delete project folder task - Files stay") {
    DSPreviewPair {
        ProjectFolderDeleteConfirmation(title: "Delete this task?", cancel: {}, confirm: {})
    }
}
#endif
