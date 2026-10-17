import Foundation

/// A long-running objective on a task: what it is, where it stands, and what it has spent. Shaped
/// like the neutral goal snapshot Claude's adapter publishes, plus Native's budget accounting.
public nonisolated struct Goal: Codable, Hashable, Sendable {
    public var objective: String
    public var budget: GoalBudget
    public var status: GoalStatus
    /// Turns that ended while the goal was active.
    public var iterations: Int
    /// The note on the agent's latest status line, or why Native changed the status.
    public var lastReason: String?
    public let createdAt: Date
    public var updatedAt: Date
    /// Active time banked before the current stretch began.
    public private(set) var bankedDuration: TimeInterval = 0
    /// When the current active stretch began; nil while not active.
    public private(set) var activeSince: Date?
    /// The session's running cost when the goal was set. Sessions report a running total, so the
    /// goal's share is the difference.
    public var costBaseline: Double?
    public var latestCost: Double?

    public init(objective: String, budget: GoalBudget, at now: Date, sessionCost: Double?) {
        self.objective = objective
        self.budget = budget
        status = .active
        iterations = 0
        createdAt = now
        updatedAt = now
        activeSince = now
        costBaseline = sessionCost
        latestCost = sessionCost
    }

    /// Active time spent so far.
    public func elapsed(at now: Date) -> TimeInterval {
        bankedDuration + (activeSince.map { max(0, now.timeIntervalSince($0)) } ?? 0)
    }

    /// What the goal has cost, once the session has reported any cost. A goal set before the first
    /// report counts from zero, which is right for the new sessions where that happens.
    public var cost: Double? {
        latestCost.map { max(0, $0 - (costBaseline ?? 0)) }
    }

    /// Moves to `status`, starting or banking the active clock as it goes.
    public mutating func transition(to status: GoalStatus, reason: String?, at now: Date) {
        if status == .active, activeSince == nil {
            activeSince = now
        } else if status != .active, let activeSince {
            bankedDuration += max(0, now.timeIntervalSince(activeSince))
            self.activeSince = nil
        }
        self.status = status
        lastReason = reason
        updatedAt = now
    }

    /// Why the budget is used up, if it is. Checked between turns: Native never cuts a turn short
    /// for budget, since a half-finished edit is worse than a slightly late stop.
    public func exhaustedBudget(at now: Date, iterationCeiling: Int) -> String? {
        if let max = budget.maxIterations, iterations >= max {
            return "Used all \(max) \(max == 1 ? "iteration" : "iterations")"
        }
        if let max = budget.maxDuration, elapsed(at: now) >= max {
            return "Used the \(GoalUsage.durationText(max)) time budget"
        }
        if let max = budget.maxCost, let cost, cost >= max {
            return "Spent the \(GoalUsage.costText(max)) budget"
        }
        if budget.maxIterations == nil, iterations >= iterationCeiling {
            return "Reached Native's limit of \(iterationCeiling) iterations for a goal without one"
        }
        return nil
    }

    public func usage(at now: Date) -> GoalUsage {
        GoalUsage(iterations: iterations, elapsed: elapsed(at: now), cost: cost, budget: budget)
    }
}
