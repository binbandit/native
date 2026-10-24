import SwiftUI

/// The view only presents choices; the app model owns the conversation and checkout transition.
struct TaskWorkspacePicker: View {
    let session: SessionModel
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State private var options: [TaskWorkspaceOption] = []
    @State private var selection: TaskWorkspaceChoice?
    @State private var isLoading = true
    @State private var isChanging = false
    @State private var error: String?

    var body: some View {
        TaskWorkspacePickerContent(
            options: options, selection: $selection, isLoading: isLoading, isChanging: isChanging, error: error,
            cancel: { dismiss() }, retry: { Task { await load() } }, apply: { Task { await apply() } }
        )
        .interactiveDismissDisabled(isChanging)
        .task { await load() }
    }

    private func load() async {
        isLoading = true
        error = nil
        defer { isLoading = false }
        do { options = try await app.workspaceOptions(for: session) } catch { self.error = error.localizedDescription }
    }

    private func apply() async {
        guard let selection else { return }
        isChanging = true
        error = nil
        defer { isChanging = false }
        do {
            _ = try await app.changeWorkspace(of: session, to: selection)
            dismiss()
        } catch {
            self.error = "\(error.localizedDescription) Your draft is still in the original task."
        }
    }
}

extension View {
    func taskWorkspacePresentation(session: SessionModel) -> some View {
        sheet(
            isPresented: Binding(
                get: { session.isWorkspacePickerRequested }, set: { session.isWorkspacePickerRequested = $0 })
        ) {
            TaskWorkspacePicker(session: session)
        }
    }
}

#if DEBUG
#Preview("Workspace picker - Loading") {
    DSPreviewPair {
        TaskWorkspacePickerContent(
            options: [], selection: .constant(nil), isLoading: true, isChanging: false, error: nil,
            cancel: {}, retry: {}, apply: {})
    }
}

#Preview("Workspace picker - Notice-only task") {
    let app = AppModel.preview(.empty)
    let session = SessionModel.preview(in: app)
    let _ = session?.addNotice("The previous worktree was kept because its agent could not be closed.", isError: false)
    DSPreviewPair {
        if let session {
            VStack(spacing: DS.Space.lg) {
                TranscriptView(session: session) { _ in }
                Button("Change Workspace…") { session.requestWorkspaceChange() }
            }
            .taskWorkspacePresentation(session: session)
            .environment(app)
            .frame(width: DS.TaskWorkspace.sheetWidth, height: DS.TaskWorkspace.listHeight)
        }
    }
}
#endif
