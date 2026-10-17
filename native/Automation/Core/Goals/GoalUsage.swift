import Foundation

/// A goal's spend against its budget, worded for people: the status bar, the continuation prompt and
/// the agent all read the same figures.
nonisolated struct GoalUsage: Hashable, Sendable {
    var iterations: Int
    var elapsed: TimeInterval
    var cost: Double?
    var budget: GoalBudget

    /// "3/10", or "3" without an iteration limit.
    var iterationsText: String {
        budget.maxIterations.map { "\(iterations)/\($0)" } ?? "\(iterations)"
    }

    /// "4m/30m", or "4m".
    var elapsedText: String {
        let spent = Self.durationText(elapsed)
        return budget.maxDuration.map { "\(spent)/\(Self.durationText($0))" } ?? spent
    }

    /// "$0.42/$5.00", "$0.42", or nil when the agent hasn't reported a cost.
    var costText: String? {
        guard let cost else { return budget.maxCost.map { "–/\(Self.costText($0))" } }
        return budget.maxCost.map { "\(Self.costText(cost))/\(Self.costText($0))" } ?? Self.costText(cost)
    }

    /// The share of the tightest limit used, for a progress bar; nil without limits.
    var fractionUsed: Double? {
        let fractions = [
            budget.maxIterations.map { Double(iterations) / Double(max($0, 1)) },
            budget.maxDuration.map { elapsed / max($0, 1) },
            budget.maxCost.flatMap { limit in cost.map { $0 / max(limit, 0.01) } },
        ]
        return fractions.compactMap(\.self).max().map { min(max($0, 0), 1) }
    }

    /// What's left, for the agent: "7 iterations and 26 minutes left".
    var remainingText: String? {
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
    var isLastIteration: Bool {
        budget.maxIterations.map { iterations + 1 >= $0 } ?? false
    }

    enum DurationStyle {
        case short, full
    }

    static func durationText(_ seconds: TimeInterval, style: DurationStyle = .short) -> String {
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

    static func costText(_ amount: Double) -> String {
        amount.formatted(.currency(code: "USD").precision(.fractionLength(2)))
    }
}
