import SwiftUI

/// A workflow run: its header, then its steps as a timeline, each opening its own session beside it
/// the way subagents do. Plain values and closures in, so it renders the same in the app, in
/// previews and in tests.
struct WorkflowRunView: View {
    let run: WorkflowRun
    /// A step's session as it is now.
    let report: (WorkflowStepRun) -> WorkflowTaskReport?
    let send: (WorkflowEvent) -> Void
    /// The step whose session is open beside the run.
    @Binding var openStep: String?
    /// Whether this run's oldest gate answers ⌘Y and ⌘⇧⌫; the window decides across everything
    /// pending in view.
    var answersShortcuts = true

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DS.Space.xxl) {
                WorkflowRunHeader(run: run, send: send)
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(run.steps.enumerated()), id: \.element.id) { index, step in
                        WorkflowStepRow(
                            step: step,
                            run: run,
                            report: report(step),
                            isSelected: openStep == step.id,
                            answersShortcuts: answersShortcuts && run.oldestRequest?.id == step.id,
                            send: send,
                            onOpen: { openStep = step.id }
                        )
                        .background(alignment: .topLeading) {
                            if index < run.steps.count - 1 {
                                TimelineRail()
                            }
                        }
                    }
                }
            }
            .frame(maxWidth: AutomationMetrics.columnWidth, alignment: .leading)
            .padding(.horizontal, DS.Space.xxl)
            .padding(.vertical, DS.Space.xxl)
            .frame(maxWidth: .infinity)
        }
        .background(.dsBackground)
    }
}

/// The line from one step's glyph down to the next, through the row's padding.
private struct TimelineRail: View {
    var body: some View {
        Rectangle()
            .fill(.dsSeparator)
            .frame(width: 1)
            .padding(.top, DS.Space.md + DS.Size.rowLeading + DS.Space.xs)
            .padding(.bottom, -DS.Space.md)
            .padding(.leading, DS.Space.md + DS.Size.rowLeading / 2)
            .accessibilityHidden(true)
    }
}
