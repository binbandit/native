import SwiftUI

struct CoordinatorTaskSheet: View {
    @Bindable var editor: CoordinatorTaskEditor

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.lg) {
            Text(editor.record == nil ? "New Coordinator Task" : "Edit Assigned Tasks")
                .font(.dsHeadline)
            Text(
                "Work from \(editor.project.name)'s folder with read-only access to start. No branch or worktree is created. The coordinator can read and message only the tasks you assign."
            )
            .font(.dsBody)
            .foregroundStyle(.dsTextSecondary)
            .fixedSize(horizontal: false, vertical: true)
            if editor.record == nil {
                if editor.agents.isEmpty {
                    Text("No agent is ready. Install or sign in to an agent in Settings > Agents, then try again.")
                        .font(.dsBody)
                } else {
                    Picker("Agent", selection: $editor.agentID) {
                        ForEach(editor.agents, id: \.agent.id) { runtime in
                            Text(runtime.agent.displayName).tag(Optional(runtime.agent.id))
                        }
                    }
                }
            }
            Text("Assigned tasks").font(.dsCaptionMedium)
            if editor.choices.isEmpty {
                Text("No available tasks in this project. You can create the coordinator now and assign tasks later.")
                    .font(.dsBody).foregroundStyle(.dsTextSecondary)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: DS.Space.md) {
                        ForEach(editor.choices) { task in
                            Toggle(
                                isOn: Binding(
                                    get: { editor.selected.contains(task.id) },
                                    set: {
                                        if $0 {
                                            editor.selected.insert(task.id)
                                        } else {
                                            editor.selected.remove(task.id)
                                        }
                                    }
                                )
                            ) {
                                Text(editor.title(for: task)).font(.dsBody)
                                Text(task.agent.displayName).font(.dsCaption).foregroundStyle(.dsTextSecondary)
                            }
                            .dsHitTarget(DS.Size.minimumHitTarget)
                        }
                    }
                }
                .frame(maxHeight: DS.CoordinatorTasks.listHeight)
            }
            if !editor.unavailableSelected.isEmpty {
                Button("Remove unavailable assignments") { editor.selected.subtract(editor.unavailableSelected) }
                    .buttonStyle(.ds(.secondary, size: .medium))
            }
            Text(
                "Tasks assigned elsewhere, archived tasks and tasks on paired hosts are unavailable. Save with no tasks selected to release all assignments."
            )
            .font(.dsCaption).foregroundStyle(.dsTextTertiary)
            .fixedSize(horizontal: false, vertical: true)
            if let error = editor.error {
                Text(error).font(.dsBody).foregroundStyle(.dsDanger).textSelection(.enabled)
            }
            if editor.isSaving { LoadingStateView("Saving coordinator…") }
            HStack(spacing: DS.Space.md) {
                Spacer(minLength: 0)
                Button("Cancel") { editor.cancel() }
                    .buttonStyle(.ds(.secondary, size: .medium)).keyboardShortcut(.cancelAction)
                Button(editor.record == nil ? "Create Coordinator" : "Save Assignments") {
                    Task { await editor.save() }
                }
                .buttonStyle(.ds(.primary, size: .medium)).keyboardShortcut(.defaultAction)
                .disabled(editor.record == nil && editor.agentID == nil)
            }
        }
        .disabled(editor.isSaving)
        .padding(DS.Space.xxl)
        .frame(idealWidth: DS.CoordinatorTasks.sheetWidth, maxWidth: DS.CoordinatorTasks.sheetWidth)
        .background(.dsBackground)
        .interactiveDismissDisabled()
    }
}

extension View {
    func coordinatorTaskPresentation() -> some View { modifier(CoordinatorTaskPresentation()) }
}

private struct CoordinatorTaskPresentation: ViewModifier {
    @Environment(AppModel.self) private var app
    func body(content: Content) -> some View {
        content.sheet(
            isPresented: Binding(
                get: { app.coordinatorEditor != nil }, set: { if !$0 { app.coordinatorEditor?.cancel() } }
            )
        ) {
            if let editor = app.coordinatorEditor { CoordinatorTaskSheet(editor: editor) }
        }
    }
}

#if DEBUG
#Preview("Coordinator - Assign tasks") {
    let app = CoordinatorTaskPreviewFixtures.app()
    DSPreviewPair {
        if let project = app.previewProject(0) {
            CoordinatorTaskSheet(editor: CoordinatorTaskEditor(project: project, record: nil, app: app))
        }
    }
}

#Preview("Coordinator - Save failed") {
    let app = CoordinatorTaskPreviewFixtures.app()
    DSPreviewPair {
        if let project = app.previewProject(0) {
            let editor = CoordinatorTaskEditor(project: project, record: nil, app: app)
            let _ = editor.error = "The agent did not accept read-only access. Choose another agent and try again."
            CoordinatorTaskSheet(editor: editor)
        }
    }
}
#Preview("Coordinator - Empty project") {
    let app = CoordinatorTaskPreviewFixtures.app(empty: true)
    DSPreviewPair {
        if let project = app.previewProject(0) {
            CoordinatorTaskSheet(editor: CoordinatorTaskEditor(project: project, record: nil, app: app))
        }
    }
}

#Preview("Coordinator - Saving assignments") {
    let app = CoordinatorTaskPreviewFixtures.app()
    DSPreviewPair {
        if let project = app.previewProject(0) {
            let editor = CoordinatorTaskEditor(project: project, record: app.coordinators.first, app: app)
            let _ = editor.isSaving = true
            CoordinatorTaskSheet(editor: editor)
        }
    }
}
#endif
