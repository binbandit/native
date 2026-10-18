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

    /// "12 prompts", "1 turn", "228.4k tokens", "$1.20", "1h 4m"; "at least 3 prompts" for estimates.
    func describe(_ value: Double, isEstimate: Bool = false) -> String {
        switch self {
        case .prompts:
            let count = Int(value)
            let text = count == 1 ? "1 prompt" : "\(count) prompts"
            return isEstimate ? "at least \(text)" : text
        case .turns: return Int(value) == 1 ? "1 turn" : "\(Int(value)) turns"
        case .tokens: return "\(DSFormat.tokens(Int(value))) tokens"
        case .cost: return value.formatted(.currency(code: "USD"))
        case .time: return DSFormat.duration(value)
        }
    }
}
