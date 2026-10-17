import ACP
import SwiftUI

/// A workflow run in the window's detail column, with the open step's session in the inspector.
/// The app passes the transcript view, so this feature never reaches into the transcript's.
struct WorkflowRunScreen<Transcript: View>: View {
    let runID: WorkflowRun.ID
    /// Whether the run's oldest gate answers ⌘Y and ⌘⇧⌫ (false while an older permission request is
    /// on screen).
    var answersShortcuts = true
    @ViewBuilder let transcript: (SessionModel) -> Transcript

    @Environment(AutomationCenter.self) private var center
    @State private var openStep: String?

    var body: some View {
        if let run = center.workflows.run(runID) {
            WorkflowRunView(
                run: run,
                report: { center.workflows.report(for: $0) },
                send: { center.workflows.send($0, to: runID) },
                openStep: $openStep,
                // A permission request in the open step's session is older than anything Native
                // gated, so it keeps the keys.
                answersShortcuts: answersShortcuts && openSession(in: run)?.state.pendingPermissions.isEmpty != false
            )
            .navigationTitle(run.title)
            .navigationSubtitle(run.definition.name)
            .inspector(isPresented: Binding(get: { openStep != nil }, set: { if !$0 { openStep = nil } })) {
                if let step = openStep.flatMap(run.stepRun), let task = step.task, let session = center.host?.session(for: task) {
                    WorkflowStepInspector(step: step, send: { center.workflows.send($0, to: runID) }) {
                        transcript(session)
                    }
                    .inspectorColumnWidth(
                        min: AutomationMetrics.inspectorWidth.min,
                        ideal: AutomationMetrics.inspectorWidth.ideal,
                        max: AutomationMetrics.inspectorWidth.max
                    )
                }
            }
        } else {
            EmptyStateView("This Run Is Gone", systemImage: "point.3.connected.trianglepath.dotted", message: "Workflow runs last until Native quits. Their steps' sessions stay with their agents.")
        }
    }

    private func openSession(in run: WorkflowRun) -> SessionModel? {
        openStep.flatMap(run.stepRun)?.task.flatMap { center.host?.session(for: $0) }
    }
}
