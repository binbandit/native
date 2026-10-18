import NativeAutomation
import NativeCommands

extension CommandID {
    static let goalEdit: Self = "goal.edit"
    static let goalPauseOrResume: Self = "goal.pauseOrResume"
    static let goalClear: Self = "goal.clear"
    static let workflowRun: Self = "workflow.run"
}

extension NativeCommand {
    /// The Session menu's goal and workflow commands, for the visible session. Their keys are in
    /// docs/keyboard.md.
    static func automation(_ center: AutomationCenter) -> [NativeCommand] {
        func goal(_ context: CommandContext) -> GoalController? {
            context.session.flatMap(center.goal(for:))
        }
        return [
            NativeCommand(.goalEdit, title: "Set or Edit Goal…", category: .composer, systemImage: "target") {
                goal($0)?.isEditorRequested = true
            }
            .menuTitle { goal($0)?.goal == nil ? "Set Goal…" : "Edit Goal…" }
            .available { goal($0) != nil },

            NativeCommand(
                .goalPauseOrResume, title: "Pause or Resume Goal", category: .composer, systemImage: "pause.circle"
            ) { context in
                guard let controller = goal(context) else { return }
                if controller.goal?.status == .active {
                    controller.pause()
                } else {
                    Task { await controller.resume() }
                }
            }
            .menuTitle { goal($0)?.goal?.status == .active ? "Pause Goal" : "Resume Goal" }
            .available { context in
                guard let status = goal(context)?.goal?.status else { return false }
                return status == .active || status.isResumable
            },

            NativeCommand(.goalClear, title: "Clear Goal", category: .composer, systemImage: "xmark.circle") { context in
                guard let controller = goal(context) else { return }
                Task { await controller.clear() }
            }
            .available { goal($0)?.goal != nil },

            NativeCommand(
                .workflowRun, title: "Run Workflow…", category: .composer, systemImage: "flowchart",
                keywords: ["automation"]
            ) { _ in
                center.requestPicker()
            },
        ]
    }
}
