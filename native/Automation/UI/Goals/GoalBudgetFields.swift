import SwiftUI

/// The three optional limits of a goal's budget, each a short field that's empty for "no limit".
struct GoalBudgetFields: View {
    @Binding var budget: GoalBudget

    var body: some View {
        HStack(alignment: .top, spacing: DS.Space.lg) {
            field("Iterations", unit: "turns", value: iterations, prompt: "No limit")
            field("Time", unit: "min", value: minutes, prompt: "No limit")
            field("Spend", unit: "USD", value: cost, prompt: "No limit")
        }
    }

    private func field(_ title: String, unit: String, value: Binding<String>, prompt: String) -> some View {
        VStack(alignment: .leading, spacing: DS.Space.xs) {
            Text(title)
                .font(.dsCaptionMedium)
                .foregroundStyle(.dsTextSecondary)
            HStack(spacing: DS.Space.sm) {
                TextField(title, text: value, prompt: Text(prompt).foregroundStyle(.dsTextQuaternary))
                    .automationField()
                    .monospacedDigit()
                    .labelsHidden()
                Text(unit)
                    .font(.dsCaption)
                    .foregroundStyle(.dsTextTertiary)
                    .fixedSize()
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // Each field edits text and keeps the budget in step; anything that isn't a positive number
    // means no limit.
    private var iterations: Binding<String> {
        Binding {
            budget.maxIterations.map(String.init) ?? ""
        } set: {
            budget.maxIterations = Int($0.trimmingCharacters(in: .whitespaces)).flatMap { $0 > 0 ? $0 : nil }
        }
    }

    private var minutes: Binding<String> {
        Binding {
            budget.maxDuration.map { String(Int(($0 / 60).rounded())) } ?? ""
        } set: {
            budget.maxDuration = Double($0.trimmingCharacters(in: .whitespaces)).flatMap { $0 > 0 ? $0 * 60 : nil }
        }
    }

    private var cost: Binding<String> {
        Binding {
            budget.maxCost.map { $0.formatted(.number.precision(.fractionLength(0...2))) } ?? ""
        } set: {
            let text = $0.trimmingCharacters(in: .whitespaces).trimmingCharacters(in: CharacterSet(charactersIn: "$"))
            budget.maxCost = Double(text).flatMap { $0 > 0 ? $0 : nil }
        }
    }
}
