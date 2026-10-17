import SwiftUI

/// The Session menu's goal and workflow items, for `NativeApp` to place in its Session menu. Their
/// keys are in docs/keyboard.md.
struct AutomationMenuItems: View {
    let center: AutomationCenter
    /// The session in the focused window.
    let session: SessionModel?

    var body: some View {
        let controller = session.flatMap(center.goal(for:))
        let goal = controller?.goal
        Button(goal == nil ? "Set Goal…" : "Edit Goal…") {
            controller?.isEditorRequested = true
        }
        .keyboardShortcut("g", modifiers: [.command, .option])
        .disabled(controller == nil)

        if goal?.status == .active {
            Button("Pause Goal") { controller?.pause() }
        } else {
            Button("Resume Goal") {
                Task { await controller?.resume() }
            }
            .disabled(goal?.status.isResumable != true)
        }

        Button("Clear Goal") {
            Task { await controller?.clear() }
        }
        .disabled(goal == nil)

        Button("Run Workflow…") {
            center.isWorkflowPickerRequested = true
        }
        .keyboardShortcut("r", modifiers: [.command, .option])
    }
}
