import Foundation

/// A goal's spend against its budget. The wording here is for the engine's own text (the agent's
/// prompts and stop reasons), which can't depend on the design system; views format the same
/// figures with `DSFormat`.
public nonisolated struct GoalUsage: Hashable, Sendable {
    public var iterations: Int
    public var elapsed: TimeInterval
    public var cost: Double?
    public var budget: GoalBudget

    /// The share of the tightest limit used, for a progress bar; nil without limits.
    public var fractionUsed: Double? {
        let fractions = [
            budget.maxIterations.map { Double(iterations) / Double(max($0, 1)) },
            budget.maxDuration.map { elapsed / max($0, 1) },
            budget.maxCost.flatMap { limit in cost.map { $0 / max(limit, 0.01) } },
        ]
        return fractions.compactMap(\.self).max().map { min(max($0, 0), 1) }
    }

    /// What's left, for the agent: "7 iterations and 26 minutes left".
    public var remainingText: String? {
        var parts: [String] = []
        if let max = budget.maxIterations {
            let left = Swift.max(0, max - iterations)
            parts.append("\(left) \(left == 1 ? "iteration" : "iterations")")
        }
        if let max = budget.maxDuration {
            parts.append(Self.durationText(Swift.max(0, max - elapsed), style: .full))
        }
        if let max = budget.maxCost {
            parts.append("\(Self.costText(Swift.max(0, max - (cost ?? 0)))) of spend")
        }
        guard !parts.isEmpty else { return nil }
        return parts.formatted(.list(type: .and)) + " left"
    }

    /// Whether the next turn is the last one the iteration budget allows.
    public var isLastIteration: Bool {
        budget.maxIterations.map { iterations + 1 >= $0 } ?? false
    }

    public enum DurationStyle {
        case short, full
    }

    public static func durationText(_ seconds: TimeInterval, style: DurationStyle = .short) -> String {
        let minutes = Int((seconds / 60).rounded(.down))
        switch style {
        case .short:
            if seconds < 60 { return "\(Int(seconds))s" }
            if minutes < 60 { return "\(minutes)m" }
            return minutes % 60 == 0 ? "\(minutes / 60)h" : "\(minutes / 60)h \(minutes % 60)m"
        case .full:
            if minutes < 1 { return "under a minute" }
            if minutes < 60 { return "\(minutes) \(minutes == 1 ? "minute" : "minutes")" }
            let hours = minutes / 60
            return "\(hours) \(hours == 1 ? "hour" : "hours")" + (minutes % 60 == 0 ? "" : " \(minutes % 60) min")
        }
    }

    public static func costText(_ amount: Double) -> String {
        amount.formatted(.currency(code: "USD").precision(.fractionLength(2)))
    }
}
