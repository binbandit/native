import NativeAutomation
import SwiftUI

/// The workflow runs in this window, newest first, or what to do when there are none.
struct WorkflowRunList: View {
    let runs: [WorkflowRun]
    @Binding var selection: WorkflowRun.ID?
    let onNewRun: () -> Void

    var body: some View {
        if runs.isEmpty {
            EmptyStateView(
                "No Workflows Running",
                systemImage: "point.3.connected.trianglepath.dotted",
                message:
                    "A workflow runs a sequence of agent tasks, such as plan with one agent, implement with another and review with the first."
            ) {
                Button("Run Workflow…", action: onNewRun)
                    .buttonStyle(.ds(.primary, size: .medium))
            }
        } else {
            VStack(alignment: .leading, spacing: 0) {
                SectionHeader("Workflows") {
                    IconButton("Run Workflow…", systemImage: "plus", action: onNewRun)
                }
                ForEach(runs) { run in
                    WorkflowRunRow(run: run, isSelected: selection == run.id) { selection = run.id }
                }
            }
        }
    }
}

#if NATIVE_PREVIEWS_WIP
#Preview("Run list") {
    DSPreviewPair {
        WorkflowRunList(
            runs: AutomationPreviewFixtures.runs, selection: .constant(AutomationPreviewFixtures.runs.first?.id),
            onNewRun: {}
        )
        .frame(width: 300, height: 420)
    }
}

#Preview("Run list - Empty") {
    DSPreviewPair {
        WorkflowRunList(runs: [], selection: .constant(nil), onNewRun: {})
            .frame(width: 300, height: 320)
    }
}
#endif
