import Foundation

/// What the activity graph counts.
enum ActivityMetric: String, CaseIterable, Hashable {
    case prompts, turns, tokens, cost, time

    var title: String {
        switch self {
        case .prompts: "Prompts"
        case .turns: "Turns"
        case .tokens: "Tokens"
        case .cost: "Cost"
        case .time: "Agent time"
        }
    }

    /// A listed session means at least one prompt, so it stands in for prompts on days Native
    /// didn't record, as an estimate. Other metrics are never estimated.
    func value(of counts: ActivityCounts) -> Double {
        switch self {
        case .prompts: Double(counts.prompts > 0 ? counts.prompts : counts.listedSessions)
        case .turns: Double(counts.turns)
        case .tokens: Double(counts.tokens)
        case .cost: counts.cost
        case .time: counts.activeSeconds
        }
    }

    /// "1 turn", "3,787 turns"
    private static func count(_ value: Double, _ noun: String) -> String {
        let count = Int(value)
        return count == 1 ? "1 \(noun)" : "\(count.formatted()) \(noun)s"
    }

    /// "12 prompts", "1 turn", "228.4k tokens", "$1.20", "1h 4m"; "at least 3 prompts" for estimates.
    func describe(_ value: Double, isEstimate: Bool = false) -> String {
        switch self {
        case .prompts:
            let text = Self.count(value, "prompt")
            return isEstimate ? "at least \(text)" : text
        case .turns: return Self.count(value, "turn")
        case .tokens: return "\(DSFormat.tokens(Int(value))) tokens"
        case .cost: return value.formatted(.currency(code: "USD"))
        case .time: return DSFormat.duration(value)
        }
    }
}
