import NativeAutomation
import SwiftUI

/// The composer's goal pill and the editor it opens. The editor also opens from Session > Set Goal
/// (⌥⌘G) and from `/goal` with no objective, through `GoalController.isEditorRequested`.
struct SessionGoalControl: View {
    let session: SessionModel
    /// The pill as only its icon, when the composer is short of room.
    var showsIcon = false

    @Environment(AutomationCenter.self) private var center
    @State private var isEditing = false

    var body: some View {
        if let controller = center.goal(for: session) {
            GoalPillButton(status: controller.goal?.status, showsIcon: showsIcon) { isEditing = true }
                .popover(isPresented: $isEditing, arrowEdge: .top) {
                    GoalEditor(goal: controller.goal, agentName: session.agentName) { objective, budget in
                        isEditing = false
                        Task {
                            if controller.goal == nil {
                                await controller.set(objective: objective, budget: budget)
                            } else {
                                await controller.update(objective: objective, budget: budget)
                            }
                        }
                    } onCancel: {
                        isEditing = false
                    }
                }
                .onChange(of: controller.isEditorRequested, initial: true) { _, isRequested in
                    guard isRequested else { return }
                    isEditing = true
                    controller.isEditorRequested = false
                }
        }
    }
}

#if DEBUG
#Preview("Goal control - No goal yet") {
    let app = AppModel.preview()
    let session = SessionModel.preview(in: app, title: "Queue follow-ups while a turn runs")
    let automation = AutomationCenter(
        goalStore: GoalStore(url: URL(filePath: "/native-preview-unused/goals.json")),
        workflows: WorkflowRunner(store: nil), automations: AutomationEngine(store: nil))
    DSPreviewPair {
        if let session {
            HStack(spacing: DS.Space.lg) {
                SessionGoalControl(session: session)
                SessionGoalControl(session: session, showsIcon: true)
            }
        }
    }
    .environment(automation)
}
#endif
