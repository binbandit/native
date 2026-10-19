import ProjectActions
import SwiftUI

extension View {
    /// What the window shows for project actions outside the menus: the toast when a run ends out
    /// of sight, the question before a repo's command first runs, and a background run's output.
    func projectActionsPresentation(_ runner: ProjectActionRunner) -> some View {
        modifier(ProjectActionsPresentation(runner: runner))
    }
}

private struct ProjectActionsPresentation: ViewModifier {
    @Bindable var runner: ProjectActionRunner
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            // Under the window's header, where it covers neither the composer nor the terminal's
            // output, which are what the user looks at next.
            .overlay(alignment: .topTrailing) {
                if let toast = runner.toast {
                    ProjectActionToastView(toast: toast) { runner.toast = nil }
                        .padding(DS.Space.lg)
                        .transition(reduceMotion ? .opacity : .move(edge: .top).combined(with: .opacity))
                        .task(id: toast.id) {
                            try? await Task.sleep(for: toast.duration)
                            if runner.toast?.id == toast.id {
                                runner.toast = nil
                            }
                        }
                }
            }
            .animation(.dsPanel, value: runner.toast)
            .confirmationDialog(
                pendingTitle, isPresented: isConfirming, titleVisibility: .visible, presenting: runner.pendingRun
            ) { pending in
                Button("Run") { runner.confirmPendingRun(allowingRepository: false) }
                Button("Always Allow for \(pending.target.project.name)") {
                    runner.confirmPendingRun(allowingRepository: true)
                }
                Button("Cancel", role: .cancel) { runner.pendingRun = nil }
            } message: { pending in
                Text(
                    "\(pending.action.command)\n\nIt comes from .native/actions.json in \(pending.target.project.name)'s "
                        + "repo. Allowing the repo's commands runs its actions without asking, and lets its event "
                        + "scripts run too."
                )
            }
            .sheet(isPresented: isShowingOutput) {
                if let key = runner.shownOutput, let run = runner.output(of: key) {
                    ProjectActionOutputSheet(run: run)
                }
            }
    }

    private var pendingTitle: String {
        runner.pendingRun.map { "Run “\($0.action.name)” from the repo?" } ?? ""
    }

    private var isConfirming: Binding<Bool> {
        Binding(get: { runner.pendingRun != nil }, set: { if !$0 { runner.pendingRun = nil } })
    }

    private var isShowingOutput: Binding<Bool> {
        Binding(get: { runner.shownOutput != nil }, set: { if !$0 { runner.shownOutput = nil } })
    }
}
