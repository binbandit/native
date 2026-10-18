import Foundation
import Testing

@testable import NativeAutomation

@Suite struct GoalLoopTests {
    let start = Date(timeIntervalSince1970: 1_000_000)

    func at(_ seconds: TimeInterval) -> Date {
        start.addingTimeInterval(seconds)
    }

    /// Sends the loop's own next prompt and ends the turn with `reply`.
    func runTurn(
        _ loop: inout GoalLoop, reply: String, outcome: TurnOutcome = .ended, at seconds: TimeInterval,
        cost: Double? = nil
    ) -> String? {
        loop.turnWillStart(.goal, at: at(seconds))
        return loop.turnDidEnd(outcome, reply: reply, sessionCost: cost, at: at(seconds + 10))
    }

    @Test func kickoffThenContinuesUntilComplete() throws {
        var loop = GoalLoop(objective: "Create hello.txt", at: start)
        let kickoff = try #require(loop.nextPrompt(at: start))
        #expect(GoalPrompt(parsing: kickoff) == .kickoff(objective: "Create hello.txt"))

        let next = runTurn(&loop, reply: "Created it.\nGOAL: continuing - verify next", at: 0)
        #expect(next.flatMap(GoalPrompt.init(parsing:)) == .continuation(objective: "Create hello.txt", iteration: 2))
        #expect(loop.goal.lastReason == "verify next")

        let result1 = runTurn(&loop, reply: "GOAL: complete - cat shows hi", at: 20)
        #expect(result1 == nil)
        #expect(loop.goal.status == .complete)
        #expect(loop.goal.iterations == 2)
        #expect(loop.goal.lastReason == "cat shows hi")
    }

    @Test func blockedWaitsForTheUsersReply() {
        var loop = GoalLoop(objective: "Deploy", at: start)
        let result2 = runTurn(&loop, reply: "GOAL: blocked - need the API key", at: 0)
        #expect(result2 == nil)
        #expect(loop.goal.status == .blocked)

        loop.turnWillStart(.user, at: at(100))
        #expect(loop.goal.status == .active)
        let next = loop.turnDidEnd(.ended, reply: "Thanks, using it now.", sessionCost: nil, at: at(110))
        #expect(next != nil)
        #expect(loop.goal.iterations == 2)
    }

    @Test func unreportedRepliesKeepGoingWithAReminder() throws {
        var loop = GoalLoop(objective: "Refactor", at: start)
        let nextValue = runTurn(&loop, reply: "I did some work.", at: 0)
        let next = try #require(nextValue)
        #expect(next.contains("didn't end with a status line"))
        #expect(loop.unreportedTurns == 1)
        let afterValue = runTurn(&loop, reply: "GOAL: continuing - more", at: 20)
        let after = try #require(afterValue)
        #expect(!after.contains("didn't end with a status line"))
    }

    @Test func cancelledTurnPausesAndNeverLoops() {
        var loop = GoalLoop(objective: "x", at: start)
        let result3 = runTurn(&loop, reply: "partial", outcome: .cancelled, at: 0)
        #expect(result3 == nil)
        #expect(loop.goal.status == .paused)
        #expect(loop.nextPrompt(at: at(30)) == nil)
    }

    @Test func failedTurnPauses() {
        var loop = GoalLoop(objective: "x", at: start)
        let result4 = runTurn(&loop, reply: "", outcome: .failed("boom"), at: 0)
        #expect(result4 == nil)
        #expect(loop.goal.status == .paused)
        #expect(loop.goal.lastReason == "The turn failed: boom")
    }

    @Test func providerLimitIsLimited() {
        var loop = GoalLoop(objective: "x", at: start)
        let result5 = runTurn(&loop, reply: "", outcome: .limited("usage limit reached"), at: 0)
        #expect(result5 == nil)
        #expect(loop.goal.status == .limited)
        // Not a budget limit, so resuming is allowed.
        let result6 = loop.resume(at: at(60))
        #expect(result6)
    }

    @Test func iterationBudgetLimitsAndCompleteStillWinsOnTheLastTurn() {
        var loop = GoalLoop(objective: "x", budget: GoalBudget(maxIterations: 2), at: start)
        let result7 = runTurn(&loop, reply: "GOAL: continuing", at: 0)
        #expect(result7 != nil)
        let result8 = runTurn(&loop, reply: "GOAL: continuing", at: 20)
        #expect(result8 == nil)
        #expect(loop.goal.status == .limited)
        #expect(loop.goal.lastReason == "Used all 2 iterations")
        let result9 = loop.resume(at: at(40))
        #expect(!result9)

        var finishing = GoalLoop(objective: "x", budget: GoalBudget(maxIterations: 1), at: start)
        let result10 = runTurn(&finishing, reply: "GOAL: complete", at: 0)
        #expect(result10 == nil)
        #expect(finishing.goal.status == .complete)
    }

    @Test func extendingAnExhaustedBudgetResumes() throws {
        var loop = GoalLoop(objective: "x", budget: GoalBudget(maxIterations: 1), at: start)
        _ = runTurn(&loop, reply: "GOAL: continuing", at: 0)
        #expect(loop.goal.status == .limited)
        loop.extendBudget(at: at(20))
        #expect(loop.goal.budget.maxIterations == 2)
        let result11 = loop.resume(at: at(20))
        #expect(result11)
        let next = try #require(loop.nextPrompt(at: at(20)))
        #expect(next.contains("Pick the goal back up"))
    }

    @Test func timeBudgetCountsOnlyActiveTime() {
        var loop = GoalLoop(objective: "x", budget: GoalBudget(maxDuration: 60), at: start)
        _ = runTurn(&loop, reply: "GOAL: blocked - question", at: 0)  // active 0...10
        #expect(loop.goal.elapsed(at: at(500)) == 10)
        loop.turnWillStart(.user, at: at(500))  // active again from 500
        let result12 = loop.turnDidEnd(.ended, reply: "GOAL: continuing", sessionCost: nil, at: at(530))
        #expect(result12 != nil)
        #expect(loop.goal.elapsed(at: at(530)) == 40)
        let result13 = runTurn(&loop, reply: "GOAL: continuing", at: 540)
        #expect(result13 == nil)
        #expect(loop.goal.status == .limited)
    }

    @Test func costBudgetUsesTheSessionsRunningTotal() {
        var loop = GoalLoop(objective: "x", budget: GoalBudget(maxCost: 1), at: start, sessionCost: 3)
        let result14 = runTurn(&loop, reply: "GOAL: continuing", at: 0, cost: 3.4)
        #expect(result14 != nil)
        #expect(loop.goal.cost == 0.4 || abs((loop.goal.cost ?? 0) - 0.4) < 0.0001)
        let result15 = runTurn(&loop, reply: "GOAL: continuing", at: 20, cost: 4.1)
        #expect(result15 == nil)
        #expect(loop.goal.status == .limited)
    }

    @Test func unlimitedGoalsStopAtTheSafetyCeiling() {
        var loop = GoalLoop(objective: "x", at: start)
        var prompts = 0
        for turn in 0..<(GoalLoop.safetyIterationCeiling + 5) where loop.goal.status == .active {
            if runTurn(&loop, reply: "still going", at: TimeInterval(turn * 20)) != nil {
                prompts += 1
            }
        }
        #expect(loop.goal.status == .limited)
        #expect(loop.goal.iterations == GoalLoop.safetyIterationCeiling)
        #expect(prompts == GoalLoop.safetyIterationCeiling - 1)
    }

    @Test func goalSetDuringAUserTurnKicksOffAfterIt() throws {
        var loop = GoalLoop(objective: "x", at: start)
        loop.turnWillStart(.user, at: start)
        let nextValue = loop.turnDidEnd(.ended, reply: "answer", sessionCost: nil, at: at(5))
        let next = try #require(nextValue)
        #expect(GoalPrompt(parsing: next) == .kickoff(objective: "x"))
        #expect(loop.goal.iterations == 0)
    }

    @Test func pausedGoalIgnoresTheTurnInFlight() {
        var loop = GoalLoop(objective: "x", at: start)
        loop.turnWillStart(.goal, at: start)
        loop.pause(at: at(1))
        let result16 = loop.turnDidEnd(.ended, reply: "GOAL: continuing", sessionCost: nil, at: at(5))
        #expect(result16 == nil)
        #expect(loop.goal.status == .paused)
    }

    @Test func aPausedGoalStillCompletesWhenATurnReportsItMet() {
        var loop = GoalLoop(objective: "x", at: start)
        _ = runTurn(&loop, reply: "", outcome: .failed("The agent is no longer running."), at: 0)
        loop.turnWillStart(.user, at: at(20))
        let next = loop.turnDidEnd(.ended, reply: "GOAL: complete - cat shows done", sessionCost: nil, at: at(30))
        #expect(next == nil)
        #expect(loop.goal.status == .complete)
        #expect(loop.goal.lastReason == "cat shows done")
    }

    @Test func userMessagesDontResumeAPausedGoal() {
        var loop = GoalLoop(objective: "x", at: start)
        loop.pause(at: start)
        loop.turnWillStart(.user, at: at(1))
        #expect(loop.goal.status == .paused)
    }

    @Test func changedObjectiveIsRestated() throws {
        var loop = GoalLoop(objective: "old", at: start)
        _ = runTurn(&loop, reply: "GOAL: continuing", at: 0)
        loop.update(objective: "new", budget: .unlimited, at: at(20))
        let next = try #require(loop.nextPrompt(at: at(20)))
        #expect(GoalPrompt(parsing: next) == .kickoff(objective: "new"))
    }

    @Test func restoredActiveGoalWaitsWithoutCountingDowntime() {
        var loop = GoalLoop(objective: "x", at: start)
        _ = runTurn(&loop, reply: "GOAL: continuing", at: 0)
        loop.turnWillStart(.goal, at: at(20))
        let restored = loop.restored()
        #expect(restored.goal.status == .paused)
        #expect(restored.turnInFlight == nil)
        #expect(restored.goal.elapsed(at: at(100_000)) == 10)
    }

    @Test func roundTripsThroughJSON() throws {
        var loop = GoalLoop(
            objective: "x", budget: GoalBudget(maxIterations: 3, maxDuration: 600, maxCost: 2), at: start)
        _ = runTurn(&loop, reply: "GOAL: continuing - a", at: 0)
        let data = try JSONEncoder().encode(loop)
        #expect(try JSONDecoder().decode(GoalLoop.self, from: data) == loop)
        let budget = try JSONDecoder().decode(GoalBudget.self, from: Data(#"{"maxMinutes": 10}"#.utf8))
        #expect(budget.maxDuration == 600)
    }

    @Test func agentRunGoalsSendTheCommandOnceAndKeepNativesBudget() {
        var loop = GoalLoop(
            objective: "Ship", budget: GoalBudget(maxIterations: 3), strategy: .claudeGoalCommand, at: start)
        #expect(loop.nextPrompt(at: start) == "/goal Ship")
        loop.turnWillStart(.goal, at: start)
        let result17 = loop.turnDidEnd(.ended, reply: "Working on it", sessionCost: nil, at: at(5))
        #expect(result17 == nil)
        #expect(loop.clearPrompt == "/goal clear")
        loop.applyAgentSnapshot(status: .active, iterations: 3, lastReason: "tests", sessionCost: nil, at: at(10))
        #expect(loop.goal.status == .limited)
    }
}
