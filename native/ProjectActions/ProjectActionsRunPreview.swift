#if DEBUG
import SwiftUI
import Terminal

/// Inert render states: no project reads, commands, agents or persistent preferences.
struct ProjectActionsRunPreview: View {
    var name: String? = "Test"
    var state: ProjectActionRunState?
    var interaction = ProjectActionsRunInteraction.rest
    var finished = false
    var removed = false
    var runningNames: [String] = []

    var body: some View {
        DSPreviewPair {
            ProjectActionsRunControl(
                name: name, state: state, runningNames: runningNames, showsFinished: finished,
                isFolderRemoved: removed, shortcut: "⇧⌘R", interaction: interaction,
                perform: {}
            ) {
                if state?.isRunning == true {
                    Button("Stop Test", systemImage: "stop.fill") {}
                    Divider()
                }
                if name != nil {
                    Button("Test", systemImage: "checkmark.seal") {}
                    Button("Build", systemImage: "hammer") {}
                    Button("Lint", systemImage: "list.bullet") {}
                } else {
                    Text("No actions for native yet")
                }
                Divider()
                Button(name == nil ? "Add Action…" : "Edit Actions…", systemImage: "slider.horizontal.3") {}
            }
            .padding(DS.Space.xl)
        }
    }

    static var running: ProjectActionRunState { .running(since: .distantPast, isStopping: false) }
    static var stopping: ProjectActionRunState { .running(since: .distantPast, isStopping: true) }
    static var failed: ProjectActionRunState { .finished(.exited(status: 1, duration: .seconds(3))) }
}

#Preview("Run - Rest") { ProjectActionsRunPreview() }
#Preview("Run - Hover run") { ProjectActionsRunPreview(interaction: .hoverRun) }
#Preview("Run - Pressed") { ProjectActionsRunPreview(interaction: .pressed) }
#Preview("Run - Hover chevron") { ProjectActionsRunPreview(interaction: .hoverChevron) }
#Preview("Run - Menu open") { ProjectActionsRunPreview(interaction: .menuOpen) }
#Preview("Run - Keyboard focus") { ProjectActionsRunPreview(interaction: .focus) }
#Preview("Run - Running") { ProjectActionsRunPreview(state: ProjectActionsRunPreview.running) }
#Preview("Run - Running hover") {
    ProjectActionsRunPreview(state: ProjectActionsRunPreview.running, interaction: .hoverRun)
}
#Preview("Run - Stopping") { ProjectActionsRunPreview(state: ProjectActionsRunPreview.stopping) }
#Preview("Run - Finished") { ProjectActionsRunPreview(finished: true) }
#Preview("Run - Finished hover") { ProjectActionsRunPreview(interaction: .hoverRun, finished: true) }
#Preview("Run - Failed") { ProjectActionsRunPreview(state: ProjectActionsRunPreview.failed) }
#Preview("Run - Failed hover") {
    ProjectActionsRunPreview(state: ProjectActionsRunPreview.failed, interaction: .hoverRun)
}
#Preview("Run - Two running") {
    ProjectActionsRunPreview(name: "Lint", state: ProjectActionsRunPreview.running, runningNames: ["Test", "Lint"])
}
#Preview("Run - Running menu open") {
    ProjectActionsRunPreview(state: ProjectActionsRunPreview.running, interaction: .menuOpen)
}
#Preview("Run - No actions") { ProjectActionsRunPreview(name: nil) }
#Preview("Run - Long name") { ProjectActionsRunPreview(name: "Release Check Nightly") }
#Preview("Run - Folder removed") { ProjectActionsRunPreview(removed: true) }
#endif
