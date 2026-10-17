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

    init(goal: Goal, isWorking: Bool, agentName: String, at now: Date) {
        let usage = goal.usage(at: now)
        let isBudgetSpent = goal.exhaustedBudget(at: now, iterationCeiling: GoalLoop.safetyIterationCeiling) != nil
        glyph = AutomationGlyph(goal: goal.status, isWorking: isWorking)
        self.usage = [usage.iterationsText + (usage.budget.maxIterations == nil ? " iterations" : ""), usage.elapsedText, usage.costText]
            .compactMap(\.self)
            .joined(separator: " · ")
        fraction = usage.fractionUsed
        let reason = goal.lastReason
        switch goal.status {
        case .active:
            label = "Goal"
            let iteration = "Iteration \(goal.iterations + 1)"
            detail = isWorking ? [iteration, reason ?? "working toward the goal"].joined(separator: " · ") : "\(iteration) starts when \(agentName) is free"
            primaryAction = .pause
        case .paused:
            label = "Paused"
            detail = reason ?? "Paused"
            primaryAction = .resume
        case .blocked:
            label = "Needs you"
            detail = "\(agentName) needs you: \(reason ?? "it can't go on without your input"). Reply to continue."
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
}
