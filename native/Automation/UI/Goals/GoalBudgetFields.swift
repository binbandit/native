import NativeAutomation
import SwiftUI

/// The three optional limits of a goal's budget, each a short field that's empty for "no limit".
/// The fields keep their own text, so a half-typed "2." stays as typed while the budget follows.
struct GoalBudgetFields: View {
    @Binding var budget: GoalBudget

    @State private var iterations = ""
    @State private var minutes = ""
    @State private var cost = ""

    var body: some View {
        HStack(alignment: .top, spacing: DS.Space.lg) {
            field("Iterations", unit: "turns", text: $iterations)
            field("Time", unit: "min", text: $minutes)
            field("Spend", unit: "USD", text: $cost)
        }
        .onAppear {
            iterations = budget.maxIterations.map(String.init) ?? ""
            minutes = budget.maxDuration.map { String(Int(($0 / 60).rounded())) } ?? ""
            cost = budget.maxCost.map { $0.formatted(.number.precision(.fractionLength(0...2))) } ?? ""
        }
        .onChange(of: iterations) { budget.maxIterations = Self.positive(iterations).map { Int($0) } }
        .onChange(of: minutes) { budget.maxDuration = Self.positive(minutes).map { $0 * 60 } }
        .onChange(of: cost) { budget.maxCost = Self.positive(cost) }
    }

    private func field(_ title: String, unit: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: DS.Space.xs) {
            Text(title)
                .font(.dsCaptionMedium)
                .foregroundStyle(.dsTextSecondary)
            HStack(spacing: DS.Space.sm) {
                AutomationTextField(label: title, text: text, placeholder: "No limit")
                    .monospacedDigit()
                Text(unit)
                    .font(.dsCaption)
                    .foregroundStyle(.dsTextTertiary)
                    .fixedSize()
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Anything that isn't a positive number means no limit.
    private static func positive(_ text: String) -> Double? {
        let trimmed = text.trimmingCharacters(in: .whitespaces).trimmingCharacters(in: CharacterSet(charactersIn: "$"))
        return Double(trimmed).flatMap { $0 > 0 ? $0 : nil }
    }
}
