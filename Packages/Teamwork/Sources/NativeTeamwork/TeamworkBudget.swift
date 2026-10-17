import Foundation

/// What a whole crew may spend: cost across every member's session, and active time. Both
/// optional. Checked between turns, never mid-turn, like a goal's budget.
public nonisolated struct TeamworkBudget: Codable, Hashable, Sendable {
    /// In the sessions' billing currency. Agents that don't report cost don't count toward it.
    public var maxCost: Double?
    /// Wall time with any member working.
    public var maxDuration: TimeInterval?

    public init(maxCost: Double? = nil, maxDuration: TimeInterval? = nil) {
        self.maxCost = maxCost
        self.maxDuration = maxDuration
    }

    public static let unlimited = TeamworkBudget()

    public var isUnlimited: Bool {
        maxCost == nil && maxDuration == nil
    }

    /// Why the budget is used up, if it is.
    public func exhausted(cost: Double?, active: TimeInterval) -> String? {
        if let maxCost, let cost, cost >= maxCost {
            return "Spent the \(Self.costText(maxCost)) budget"
        }
        if let maxDuration, active >= maxDuration {
            return "Used the \(Self.durationText(maxDuration)) time budget"
        }
        return nil
    }

    /// The same budget again on top of what's been spent.
    public func extended(cost: Double?, active: TimeInterval) -> TeamworkBudget {
        TeamworkBudget(maxCost: maxCost.map { (cost ?? 0) + $0 }, maxDuration: maxDuration.map { active + $0 })
    }

    static func costText(_ amount: Double) -> String {
        amount.formatted(.currency(code: "USD").precision(.fractionLength(2)))
    }

    static func durationText(_ seconds: TimeInterval) -> String {
        let minutes = Int((seconds / 60).rounded())
        return minutes >= 60 ? "\(minutes / 60)h\(minutes % 60 == 0 ? "" : " \(minutes % 60)m")" : "\(max(1, minutes))m"
    }
}
