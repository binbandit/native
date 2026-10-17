import SwiftUI

/// The workflow picker, bound to the app: runs start in `cwd` (the current project's folder), and
/// `onStarted` gets the new run so the window can show it.
struct WorkflowPickerSheet: View {
    let cwd: URL
    let onStarted: (WorkflowRun.ID) -> Void

    @Environment(AutomationCenter.self) private var center
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        WorkflowPickerView(
            entries: center.library.entries,
            agents: center.host?.workflowAgents ?? [],
            projectName: cwd.lastPathComponent,
            plan: { center.workflows.plan(for: $0, overrides: $1) },
            onRun: { definition, input, overrides in
                let run = center.workflows.start(definition, input: input, cwd: cwd, overrides: overrides)
                dismiss()
                onStarted(run)
            },
            onCancel: { dismiss() }
        )
    }
}
