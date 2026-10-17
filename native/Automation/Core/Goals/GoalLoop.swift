import Foundation

/// The goal state machine. It never talks to an agent: callers report turns starting and ending,
/// and it answers with the next prompt to send, if any. Values in, values out, so every rule here
/// is testable without a session.
///
/// Rules: after a turn ends while the goal is active, the agent's status line decides what's next
/// (complete, blocked, or another turn). A reply without one counts as "continuing" so an agent
/// that ignores the protocol still gets driven, within budget. A cancelled or failed turn pauses
/// the goal and a provider limit makes it limited, so Native never loops on an error.
nonisolated struct GoalLoop: Codable, Hashable, Sendable {
    /// Who sent the prompt that started a turn.
    enum Origin: String, Codable, Hashable, Sendable {
        case goal, user
    }

    /// How the goal is carried out. Native's own loop works with any agent; an agent with its own
    /// goal command can run the loop itself while Native keeps the budget.
    enum Strategy: String, Codable, Hashable, Sendable {
        /// Native sends a continuation after each turn and reads the status line.
        case native
        /// Claude Code's `/goal <condition>` (a Stop-hook loop). Status arrives as adapter
        /// snapshots through `applyAgentSnapshot`.
        case claudeGoalCommand
    }

    /// The most turns a goal without an iteration limit gets, so a goal never runs away.
    static let safetyIterationCeiling = 100

    private(set) var goal: Goal
    let strategy: Strategy
    /// The agent hasn't been told about the goal yet; the next goal prompt is the kickoff.
    private(set) var needsKickoff = true
    /// Who started the turn that's running, if one is.
    private(set) var turnInFlight: Origin?
    /// Goal turns in a row whose reply had no status line.
    private(set) var unreportedTurns = 0
    /// The goal was picked back up after a pause; the next continuation says so.
    private var isResuming = false

    init(objective: String, budget: GoalBudget = .unlimited, strategy: Strategy = .native, at now: Date, sessionCost: Double? = nil) {
        goal = Goal(objective: objective, budget: budget, at: now, sessionCost: sessionCost)
        self.strategy = strategy
    }

    /// The prompt Native should send when the agent is free, or nil when it shouldn't send one.
    func nextPrompt(at now: Date) -> String? {
        guard goal.status == .active else { return nil }
        let usage = goal.usage(at: now)
        switch strategy {
        case .native:
            if needsKickoff {
                return GoalPrompt.kickoffText(objective: goal.objective, usage: usage)
            }
            return GoalPrompt.continuationText(objective: goal.objective, usage: usage, reminder: unreportedTurns > 0, resumed: isResuming)
        case .claudeGoalCommand:
            // The agent's own loop continues on its own; it only needs to be told once.
            return needsKickoff ? "/goal \(goal.objective)" : nil
        }
    }

    /// The prompt that tells the agent to drop its own goal, for strategies where it keeps one.
    var clearPrompt: String? {
        strategy == .claudeGoalCommand && !needsKickoff ? "/goal clear" : nil
    }

    // MARK: - Turns

    mutating func turnWillStart(_ origin: Origin, at now: Date) {
        turnInFlight = origin
        switch origin {
        case .goal:
            needsKickoff = false
            isResuming = false
        case .user where goal.status == .blocked:
            // The agent asked the user for something; their reply is the answer, so work resumes.
            goal.transition(to: .active, reason: "You replied", at: now)
        case .user:
            break
        }
    }

    /// Records a finished turn and returns the prompt to send next, if the goal goes on. A turn
    /// that ended before the agent heard about the goal doesn't count against it.
    mutating func turnDidEnd(_ outcome: TurnOutcome, reply: String?, sessionCost: Double?, at now: Date) -> String? {
        let origin = turnInFlight
        turnInFlight = nil
        if let sessionCost {
            goal.latestCost = sessionCost
        }
        guard goal.status == .active else { return nil }
        if needsKickoff, origin != .goal {
            return handlePreGoalTurn(outcome, at: now)
        }
        goal.iterations += 1
        goal.updatedAt = now
        switch outcome {
        case .cancelled:
            goal.transition(to: .paused, reason: "Stopped during iteration \(goal.iterations)", at: now)
        case .failed(let message):
            goal.transition(to: .paused, reason: "The turn failed: \(message)", at: now)
        case .limited(let message):
            goal.transition(to: .limited, reason: message, at: now)
        case .refused:
            goal.transition(to: .blocked, reason: "The agent declined to continue", at: now)
        case .ended:
            return handleEndedTurn(reply: reply, at: now)
        }
        return nil
    }

    private mutating func handlePreGoalTurn(_ outcome: TurnOutcome, at now: Date) -> String? {
        switch outcome {
        case .ended:
            return nextPrompt(at: now)
        case .cancelled:
            goal.transition(to: .paused, reason: "Stopped before the goal started", at: now)
        case .failed(let message):
            goal.transition(to: .paused, reason: "The turn failed: \(message)", at: now)
        case .limited(let message):
            goal.transition(to: .limited, reason: message, at: now)
        case .refused:
            goal.transition(to: .blocked, reason: "The agent declined to continue", at: now)
        }
        return nil
    }

    private mutating func handleEndedTurn(reply: String?, at now: Date) -> String? {
        let marker = reply.flatMap(GoalMarker.init(parsing:))
        switch marker?.status {
        case .complete:
            goal.transition(to: .complete, reason: marker?.note ?? "The agent reported the goal met", at: now)
            return nil
        case .blocked:
            goal.transition(to: .blocked, reason: marker?.note ?? "The agent needs your input", at: now)
            return nil
        case .continuing, nil:
            unreportedTurns = marker == nil ? unreportedTurns + 1 : 0
            goal.lastReason = marker?.note ?? goal.lastReason
            if let exhausted = goal.exhaustedBudget(at: now, iterationCeiling: Self.safetyIterationCeiling) {
                goal.transition(to: .limited, reason: exhausted, at: now)
                return nil
            }
            return nextPrompt(at: now)
        }
    }

    // MARK: - User actions

    /// Stops driving the agent after the current turn. The turn itself runs on; use cancel for that.
    mutating func pause(at now: Date, reason: String = "Paused by you") {
        guard goal.status == .active else { return }
        goal.transition(to: .paused, reason: reason, at: now)
    }

    /// The goal as found on the next launch. Nothing drove it while Native was closed, so an active
    /// goal waits for the user, and its clock stops at the last thing that happened.
    func restored() -> GoalLoop {
        var loop = self
        loop.turnInFlight = nil
        if loop.goal.status == .active {
            loop.goal.transition(to: .paused, reason: "Native closed while this goal was running", at: goal.updatedAt)
        }
        return loop
    }

    /// Picks the goal back up. A goal whose budget is spent stays limited until the budget grows,
    /// so `resume` never sneaks past a limit. Returns whether it's active again.
    @discardableResult
    mutating func resume(at now: Date) -> Bool {
        guard goal.status.isResumable else { return goal.status == .active }
        if goal.exhaustedBudget(at: now, iterationCeiling: Self.safetyIterationCeiling) != nil {
            return false
        }
        goal.transition(to: .active, reason: goal.status == .blocked ? "Resumed by you" : nil, at: now)
        isResuming = !needsKickoff
        return true
    }

    mutating func update(objective: String, budget: GoalBudget, at now: Date) {
        if objective != goal.objective {
            // A changed objective has to reach the agent, so the next goal prompt restates it.
            needsKickoff = true
            goal.objective = objective
        }
        goal.budget = budget
        goal.updatedAt = now
    }

    /// Grants the same budget again on top of what's been spent.
    mutating func extendBudget(at now: Date) {
        goal.budget = goal.budget.extended(beyond: goal, at: now)
        goal.updatedAt = now
    }

    // MARK: - Agent-run goals

    /// Applies the agent's own report of its goal (`claudeGoalCommand`). Native still enforces the
    /// budget: when it's spent, the goal is limited and the caller sends `clearPrompt`.
    mutating func applyAgentSnapshot(status: GoalStatus, iterations: Int, lastReason: String?, sessionCost: Double?, at now: Date) {
        guard strategy == .claudeGoalCommand else { return }
        goal.iterations = max(goal.iterations, iterations)
        if let sessionCost {
            goal.latestCost = sessionCost
        }
        if status != goal.status || lastReason != goal.lastReason {
            goal.transition(to: status, reason: lastReason, at: now)
        }
        if goal.status == .active, let exhausted = goal.exhaustedBudget(at: now, iterationCeiling: Self.safetyIterationCeiling) {
            goal.transition(to: .limited, reason: exhausted, at: now)
        }
    }
}
