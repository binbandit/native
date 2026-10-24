import NativeAutomation
import SwiftUI

/// The same save path whether the goal opens from its pill or the composer's settings door.
struct SessionGoalEditor: View {
    let controller: GoalController
    let agentName: String
    let onDismiss: () -> Void

    var body: some View {
        GoalEditor(goal: controller.goal, agentName: agentName) { objective, budget in
            onDismiss()
            Task {
                if controller.goal == nil {
                    await controller.set(objective: objective, budget: budget)
                } else {
                    await controller.update(objective: objective, budget: budget)
                }
            }
        } onCancel: {
            onDismiss()
        }
    }
}

#if DEBUG
#Preview("Task goal editor - New and existing") {
    let fresh = GoalController(store: nil, storageKey: nil)
    let existing = GoalController(store: nil, storageKey: nil)
    DSPreviewPair {
        HStack {
            SessionGoalEditor(controller: fresh, agentName: "Codex", onDismiss: {})
            if existing.goal != nil {
                SessionGoalEditor(controller: existing, agentName: "Codex", onDismiss: {})
            }
        }
    }
    .task {
        await existing.set(objective: "Keep queued messages in place", budget: GoalBudget(maxIterations: 1))
    }
}
#endif
