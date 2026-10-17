import NativeAutomation
import SwiftUI

/// The session's goal as the composer's top section, when it has one. Put it above the queued
/// messages and the plan, with a divider after it.
struct SessionGoalBar: View {
    let session: SessionModel

    @Environment(AutomationCenter.self) private var center

    var body: some View {
        if let controller = center.goal(for: session), let goal = controller.goal {
            GoalSection(
                goal: goal,
                isWorking: session.phase == .prompting,
                agentName: session.agentName,
                actions: GoalSection.Actions(
                    pause: { controller.pause() },
                    resume: { Task { await controller.resume() } },
                    extendAndResume: { Task { await controller.extendAndResume() } },
                    clear: { Task { await controller.clear() } },
                    edit: { controller.isEditorRequested = true }
                )
            )
        }
    }
}
