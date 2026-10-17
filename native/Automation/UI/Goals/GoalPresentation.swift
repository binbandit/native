import Foundation

/// What the goal bar says about a goal: its label, what it's doing or why it stopped, its spend, and
/// the one action that moves it on. Kept apart from the view so every state's wording is in one
/// place.
struct GoalPresentation: Hashable {
    enum Action: Hashable {
        case pause, resume, extendAndResume, clear
    }

    let glyph: AutomationGlyph
    let label: String
    let detail: String
    let usage: String
    /// The share of the tightest budget used; nil without a budget.
    let fraction: Double?
    let primaryAction: Action?

    /// Spelled out for the tooltip, since the bar's figures are terse.
    let usageHelp: String

    init(goal: Goal, isWorking: Bool, agentName: String, at now: Date) {
        let usage = goal.usage(at: now)
        let isBudgetSpent = goal.exhaustedBudget(at: now, iterationCeiling: GoalLoop.safetyIterationCeiling) != nil
        glyph = AutomationGlyph(goal: goal.status, isWorking: isWorking)
        // A cost of nothing against no cost budget says nothing, so it's left out.
        let iterations = usage.budget.maxIterations.map { "\(usage.iterations)/\($0)" } ?? "\(usage.iterations) iterations"
        // Whole minutes past the first: the bar refreshes every 15 seconds, and ticking seconds are noise.
        let elapsed = DSFormat.duration(usage.elapsed < 60 ? usage.elapsed : (usage.elapsed / 60).rounded(.down) * 60)
            + (usage.budget.maxDuration.map { "/" + DSFormat.duration($0) } ?? "")
        // A cost of nothing against no cost budget says nothing, so it's left out.
        let cost: String? = switch (usage.cost, usage.budget.maxCost) {
        case (let spent?, let limit?): "\(DSFormat.cost(spent))/\(DSFormat.cost(limit))"
        case (nil, let limit?): "–/\(DSFormat.cost(limit))"
        case (let spent?, nil) where spent > 0: DSFormat.cost(spent)
        default: nil
        }
        self.usage = [iterations, elapsed, cost].compactMap(\.self).joined(separator: " · ")
        fraction = usage.fractionUsed
        usageHelp = ["Iterations: \(iterations)", "active time: \(elapsed)", cost.map { "spend: \($0)" }]
            .compactMap(\.self)
            .joined(separator: ", ")
        let reason = goal.lastReason
        switch goal.status {
        case .active:
            label = "Goal"
            let iteration = "Iteration \(goal.iterations + 1)" + (goal.budget.maxIterations.map { " of \($0)" } ?? "")
            detail = isWorking ? [iteration, reason ?? "working toward the goal"].joined(separator: " · ") : "\(iteration) starts when \(agentName) is free"
            primaryAction = .pause
        case .paused:
            label = "Paused"
            detail = reason ?? "Paused"
            primaryAction = .resume
        case .blocked:
            label = "Needs you"
            detail = "\(agentName) needs you: \(Self.sentence(reason ?? "it can't go on without your input")) Reply to continue."
            primaryAction = .resume
        case .limited:
            label = isBudgetSpent ? "Budget used" : "Limited"
            detail = reason ?? (isBudgetSpent ? "The budget is used up" : "The provider stopped the agent at a limit")
            primaryAction = isBudgetSpent ? .extendAndResume : .resume
        case .complete:
            label = "Complete"
            detail = reason.map { "Done: \($0)" } ?? "\(agentName) reported the goal met"
            primaryAction = .clear
        }
    }

    /// Ends `text` with a period unless it already ends a sentence.
    private static func sentence(_ text: String) -> String {
        guard let last = text.last, !".?!".contains(last) else { return text }
        return text + "."
    }
}
