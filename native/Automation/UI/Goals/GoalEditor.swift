import SwiftUI

/// Sets or edits a task's goal: the objective and an optional budget. Shown as a popover from the
/// composer's goal pill, or from Session > Set Goal (⌥⌘G).
struct GoalEditor: View {
    /// The goal being edited, or nil to set a new one.
    let goal: Goal?
    let agentName: String
    let onSave: (_ objective: String, _ budget: GoalBudget) -> Void
    let onCancel: () -> Void

    @State private var objective: String
    @State private var budget: GoalBudget

    init(goal: Goal?, agentName: String, onSave: @escaping (_ objective: String, _ budget: GoalBudget) -> Void, onCancel: @escaping () -> Void) {
        self.goal = goal
        self.agentName = agentName
        self.onSave = onSave
        self.onCancel = onCancel
        // Seeded here rather than on appear, so the budget fields read the goal's budget first.
        _objective = State(initialValue: goal?.objective ?? "")
        _budget = State(initialValue: goal?.budget ?? GoalBudget(maxIterations: 10))
    }

    private var canSave: Bool {
        !objective.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.lg) {
            VStack(alignment: .leading, spacing: DS.Space.xs) {
                Text(goal == nil ? "Set a Goal" : "Edit Goal")
                    .font(.dsHeadline)
                    .foregroundStyle(.dsTextPrimary)
                Text("\(agentName) keeps working, turn after turn, until the goal is met, it needs you, or the budget runs out.")
                    .font(.dsCaption)
                    .foregroundStyle(.dsTextSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .tracking(DS.Tracking.tight)

            VStack(alignment: .leading, spacing: DS.Space.xs) {
                Text("Objective")
                    .font(.dsCaptionMedium)
                    .foregroundStyle(.dsTextSecondary)
                AutomationTextField(
                    label: "Objective",
                    text: $objective,
                    placeholder: "Every test in ExportTests passes, and the CSV matches the spec",
                    axis: .vertical,
                    lines: 3...8
                )
                .focusedOnAppear()
                Text("Say how to tell it's done; the agent verifies that before it reports the goal complete.")
                    .font(.dsCaption)
                    .foregroundStyle(.dsTextTertiary)
            }

            VStack(alignment: .leading, spacing: DS.Space.sm) {
                GoalBudgetFields(budget: $budget)
                Text(budgetNote)
                    .font(.dsCaption)
                    .foregroundStyle(.dsTextTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(spacing: DS.Space.md) {
                if let goal {
                    Text("\(goal.iterations) \(goal.iterations == 1 ? "iteration" : "iterations") so far carry over.")
                        .font(.dsCaption)
                        .foregroundStyle(.dsTextTertiary)
                }
                Spacer(minLength: 0)
                Button("Cancel", action: onCancel)
                    .buttonStyle(.ds(.secondary, size: .medium))
                    .keyboardShortcut(.cancelAction)
                Button(goal == nil ? "Set Goal" : "Save Goal") {
                    onSave(objective, budget)
                }
                .buttonStyle(.ds(.primary, size: .medium))
                .keyboardShortcut(.defaultAction)
                .disabled(!canSave)
            }
        }
        .padding(DS.Space.xl)
        .frame(width: AutomationMetrics.goalEditorWidth)
        .background(.dsOverlay)
    }

    private var budgetNote: String {
        if budget.maxIterations == nil {
            return "Leave a limit empty for none. Without an iteration limit, Native stops after \(GoalLoop.safetyIterationCeiling)."
        }
        return "Leave a limit empty for none. Native checks the budget between turns, never in the middle of one."
    }
}
