import Testing

@testable import NativeAutomation

@Suite struct GoalMarkerTests {
    @Test(arguments: [
        (
            "Done.\n\nGOAL: complete - hello.txt exists and contains hi", GoalMarker.Status.complete,
            "hello.txt exists and contains hi" as String?
        ),
        ("**GOAL: complete** - all 12 tests pass", .complete, "all 12 tests pass"),
        ("`GOAL: blocked - need the staging API key`", .blocked, "need the staging API key"),
        ("GOAL: continuing — next I'll wire the view", .continuing, "next I'll wire the view"),
        ("Goal status: done", .complete, nil),
        ("GOAL: not complete - two tests still fail", .continuing, "two tests still fail"),
        ("GOAL: In progress: refactoring", .continuing, "refactoring"),
        ("- GOAL: complete (verified with cat).", .complete, "verified with cat)."),
        ("GOAL：complete", .complete, nil),
    ])
    func parsesStatusLines(reply: String, status: GoalMarker.Status, note: String?) {
        let marker = GoalMarker(parsing: reply)
        #expect(marker?.status == status)
        #expect(marker?.note == note)
    }

    @Test(arguments: [
        "Goal: complete the migration by Friday",
        "The goal: complete is what I'll report later.",
        "GOAL: completeness check",
        "I set the GOAL: complete flag",
        "No marker here",
        "",
    ])
    func ignoresProse(reply: String) {
        #expect(GoalMarker(parsing: reply) == nil)
    }

    @Test func lastMarkerWins() {
        let reply = "GOAL: continuing - first\nmore work\nGOAL: complete - finally"
        #expect(GoalMarker(parsing: reply) == GoalMarker(status: .complete, note: "finally"))
    }

    @Test func echoedInstructionsAreNotAReport() {
        let reply = "I'll end each reply with one of:\n" + GoalPrompt.protocolLines
        #expect(GoalMarker(parsing: reply) == nil)
    }

    @Test func markerFarFromTheEndIsIgnored() {
        let reply = "GOAL: complete - early\n" + (1...8).map { "line \($0)" }.joined(separator: "\n")
        #expect(GoalMarker(parsing: reply) == nil)
    }

    @Test func signOffAfterTheMarkerIsAllowed() {
        let reply = "Work.\nGOAL: blocked - which database?\n\nLet me know!"
        #expect(GoalMarker(parsing: reply)?.status == .blocked)
    }

    @Test func strippingRemovesOnlyTheStatusLine() {
        let reply = "Summary of changes.\n\nGOAL: complete - verified"
        #expect(GoalMarker.stripping(reply) == "Summary of changes.")
        #expect(GoalMarker.stripping("No marker") == "No marker")
    }
}

@Suite struct GoalPromptTests {
    @Test func kickoffRoundTrips() {
        let usage = Goal(objective: "x", budget: GoalBudget(maxIterations: 5), at: .now, sessionCost: nil).usage(
            at: .now)
        let text = GoalPrompt.kickoffText(objective: "Make the tests pass\nall of them", usage: usage)
        #expect(GoalPrompt(parsing: text) == .kickoff(objective: "Make the tests pass\nall of them"))
        #expect(text.contains("Budget: 5 iterations."))
    }

    @Test func continuationRoundTrips() {
        var goal = Goal(objective: "Ship it", budget: GoalBudget(maxIterations: 4), at: .now, sessionCost: nil)
        goal.iterations = 3
        let text = GoalPrompt.continuationText(
            objective: "Ship it", usage: goal.usage(at: .now), reminder: true, resumed: false)
        #expect(GoalPrompt(parsing: text) == .continuation(objective: "Ship it", iteration: 4))
        #expect(text.contains("last iteration"))
        #expect(text.contains("didn't end with a status line"))
    }

    @Test func ordinaryPromptsAreNotGoalPrompts() {
        #expect(GoalPrompt(parsing: "<goal> inline") == nil)
        #expect(GoalPrompt(parsing: "Fix the bug") == nil)
    }
}

@Suite struct GoalCommandTests {
    @Test(arguments: [
        ("/goal Make CI green", GoalCommand.set(objective: "Make CI green")),
        ("  /goal  ", .edit),
        ("/goal pause", .pause),
        ("/goal Resume", .resume),
        ("/goal clear", .clear),
        ("/goal stop", .clear),
    ])
    func parses(draft: String, command: GoalCommand) {
        #expect(GoalCommand(parsing: draft) == command)
    }

    @Test func otherCommandsPassThrough() {
        #expect(GoalCommand(parsing: "/goals") == nil)
        #expect(GoalCommand(parsing: "please /goal this") == nil)
    }
}

@Suite struct TurnOutcomeTests {
    @Test func limitErrorsReadAsLimits() {
        #expect(
            TurnOutcome.failure("Claude AI usage limit reached|1760000000")
                == .limited("Claude AI usage limit reached|1760000000"))
        #expect(TurnOutcome.failure("429 Too Many Requests") == .limited("429 Too Many Requests"))
        #expect(TurnOutcome.failure("Internal error") == .failed("Internal error"))
    }
}
