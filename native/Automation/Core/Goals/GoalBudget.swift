import Foundation

/// How much a goal may spend before Native stops it. Every limit is optional; a goal with none
/// still stops at `GoalLoop.safetyIterationCeiling`.
nonisolated struct GoalBudget: Hashable, Sendable {
    var maxIterations: Int?
    /// Wall time the goal may spend active. Time paused or blocked on the user doesn't count.
    var maxDuration: TimeInterval?
    /// In the session's billing currency. Agents that don't report cost can't be held to it.
    var maxCost: Double?

    init(maxIterations: Int? = nil, maxDuration: TimeInterval? = nil, maxCost: Double? = nil) {
        self.maxIterations = maxIterations
        self.maxDuration = maxDuration
        self.maxCost = maxCost
    }

    static let unlimited = GoalBudget()

    var isUnlimited: Bool {
        maxIterations == nil && maxDuration == nil && maxCost == nil
    }

    /// The budget again on top of what's been used, for picking a limited goal back up.
    func extended(beyond goal: Goal, at now: Date) -> GoalBudget {
        GoalBudget(
            maxIterations: maxIterations.map { goal.iterations + $0 },
            maxDuration: maxDuration.map { goal.elapsed(at: now) + $0 },
            maxCost: maxCost.map { (goal.cost ?? 0) + $0 }
        )
    }
}

// Workflow definitions are written by hand, so the JSON says minutes rather than seconds.
extension GoalBudget: Codable {
    private enum CodingKeys: String, CodingKey {
        case maxIterations, maxMinutes, maxCost
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        maxIterations = try container.decodeIfPresent(Int.self, forKey: .maxIterations)
        maxDuration = try container.decodeIfPresent(Double.self, forKey: .maxMinutes).map { $0 * 60 }
        maxCost = try container.decodeIfPresent(Double.self, forKey: .maxCost)
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(maxIterations, forKey: .maxIterations)
        try container.encodeIfPresent(maxDuration.map { $0 / 60 }, forKey: .maxMinutes)
        try container.encodeIfPresent(maxCost, forKey: .maxCost)
    }
}
