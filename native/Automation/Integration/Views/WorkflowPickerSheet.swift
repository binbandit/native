import NativeAutomation
import SwiftUI

/// The workflow picker, bound to the app: runs start in `cwd` (the current project's folder), and
/// `onStarted` gets the new run so the window can show it. Without a project there's nothing to run
/// in, so it says so and offers to open one.
struct WorkflowPickerSheet: View {
    @Environment(\.projectDisplayName) private var projectDisplayName

    let cwd: URL?
    let onAddProject: () -> Void
    let onStarted: (WorkflowRun.ID) -> Void

    @Environment(AutomationCenter.self) private var center
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        if let cwd {
            WorkflowPickerView(
                entries: center.library.entries,
                agents: center.host?.workflowAgents ?? [],
                projectName: projectDisplayName(cwd),
                plan: { center.workflows.plan(for: $0, overrides: $1) },
                onRun: { definition, input, overrides in
                    let run = center.workflows.start(definition, input: input, cwd: cwd, overrides: overrides)
                    dismiss()
                    onStarted(run)
                },
                onCancel: { dismiss() },
                initialSelection: center.pickerSelection
            )
        } else {
            EmptyStateView(
                "Open a Project First", systemImage: "folder", message: "A workflow's steps work in a project's folder."
            ) {
                Button("Cancel") { dismiss() }
                    .buttonStyle(.ds(.secondary, size: .medium))
                Button("Open Folder…") {
                    dismiss()
                    onAddProject()
                }
                .buttonStyle(.ds(.primary, size: .medium))
            }
            .frame(width: AutomationMetrics.goalEditorWidth, height: 240)
        }
    }
}

#if NATIVE_PREVIEWS_WIP
#Preview("Workflow picker sheet") {
    DSPreviewPair {
        // No host is connected, so it lists the library with no agents to run it on.
        WorkflowPickerSheet(cwd: AutomationPreviewFixtures.project, onAddProject: {}, onStarted: { _ in })
    }
    .environment(AutomationCenter.preview())
}

#Preview("Workflow picker sheet - No project") {
    DSPreviewPair {
        WorkflowPickerSheet(cwd: nil, onAddProject: {}, onStarted: { _ in })
    }
    .environment(AutomationCenter.preview())
}
#endif
