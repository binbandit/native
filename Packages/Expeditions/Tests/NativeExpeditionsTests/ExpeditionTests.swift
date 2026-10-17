import Foundation
import NativeAutomation
import Testing
@testable import NativeExpeditions

@Suite struct ExpeditionTests {
    let done = "Implemented and tested.\nGOAL: complete - tests pass"

    @Test func planApproveBuildCheckDebriefAndOpenPullRequest() throws {
        var driver = ExpeditionDriver()
        driver.send(.start)
        #expect(driver.expedition.base == URL(filePath: "/worktrees/app/csv"))
        #expect(driver.created == [.lead])
        #expect(driver.lastPrompt?.text.contains("plan the route") == true)
        #expect(driver.expedition.phase == .planning)

        driver.end(.lead, "Plan below.\n```\n<route>\n\(ExpeditionDriver.twoLegs)\n</route>\n```")
        #expect(driver.expedition.phase == .reviewing)
        #expect(driver.expedition.attention.first?.kind == .routeReady)
        var route = try #require(driver.expedition.route)
        route.questions[0].answer = "Yes"
        driver.send(.approve(route))

        // One builder at a time: the stream assignment waits for the writer.
        #expect(driver.expedition.phase == .underway)
        #expect(driver.status(.assignment("writer")) == .running)
        #expect(driver.status(.assignment("stream")) == .waiting)
        let briefing = try #require(driver.lastPrompt?.text)
        #expect(briefing.contains("Your assignment, \"Add the CSV writer\""))
        #expect(briefing.contains("Quote empty cells? Yes"))
        #expect(briefing.contains("<goal>"))

        driver.end(.assignment("writer"), done, cost: 0.4)
        #expect(driver.status(.assignment("writer")) == .succeeded)
        #expect(driver.expedition.assignment("writer")?.report == "Implemented and tested.")
        #expect(driver.lastPrompt?.text.contains("What came before:\n### Add the CSV writer (Codex)") == true)
        driver.end(.assignment("stream"), done, cost: 0.3)

        // The leg's checkpoint runs in a reviewer session of its own.
        #expect(driver.created.last == .checkpoint("leg-1"))
        #expect(driver.lastPrompt?.text.contains("VERDICT: pass") == true)
        driver.end(.checkpoint("leg-1"), "Looks right.\nVERDICT: pass - ran swift test", cost: 0.2)

        // The lead looks at the legs ahead before the next one starts.
        #expect(driver.status(.checkpoint("leg-1")) == .succeeded)
        #expect(driver.lastPrompt?.slot == .lead)
        #expect(driver.status(.assignment("button")) == .waiting)
        driver.end(.lead, "The route still holds.")
        #expect(driver.status(.assignment("button")) == .running)
        driver.end(.assignment("button"), done)
        driver.end(.checkpoint("leg-2"), "VERDICT: pass")

        #expect(driver.expedition.phase == .debriefing)
        #expect(driver.lastPrompt?.text.contains("write the debrief") == true)
        driver.end(.lead, "## Summary\nCSV export is in.")
        let draft = try #require(driver.pullRequests.first)
        #expect(draft.title == "Add CSV export to reports")
        #expect(draft.body.hasPrefix("## Summary\nCSV export is in."))
        #expect(draft.cwd == URL(filePath: "/worktrees/app/csv"))

        driver.send(.pullRequestOpened(WorkflowPullRequestResult(url: try #require(URL(string: "https://github.com/o/r/pull/7")), number: 7)))
        #expect(driver.expedition.phase == .complete)
        #expect(driver.expedition.cost.map { abs($0 - 0.9) < 0.0001 } == true)
        #expect(driver.expedition.log.last?.text == "The expedition is complete.")
    }

    @Test func unreadableRouteGoesBackToTheLeadTwiceThenWaitsForTheUser() {
        var driver = ExpeditionDriver()
        driver.send(.start)
        driver.end(.lead, "I think we should just do it.")
        #expect(driver.lastPrompt?.text.hasPrefix("Native couldn't read your route") == true)
        driver.end(.lead, "<route>{ not json</route>")
        #expect(driver.lastPrompt?.text.contains("isn't valid JSON") == true)
        driver.end(.lead, "<route>{\"legs\": []}</route>")
        #expect(driver.expedition.phase == .needsYou)
        guard case .blocked = driver.status(.lead) else {
            Issue.record("The lead should be blocked")
            return
        }
        // The user's reply picks the lead back up.
        driver.send(.message(.lead, text: "Use one leg."))
        #expect(driver.status(.lead) == .running)
    }

    @Test func askingForChangesRevisesTheRouteAndKeepsAnswers() throws {
        var driver = ExpeditionDriver()
        driver.send(.start)
        driver.end(.lead, "<route>\(ExpeditionDriver.twoLegs)</route>")
        driver.send(.requestChanges("Drop streaming; reports are small."))
        #expect(driver.expedition.phase == .planning)
        #expect(driver.lastPrompt?.text.contains("Drop streaming") == true)
        let revised = ExpeditionDriver.twoLegs.replacingOccurrences(of: "Stream large reports", with: "Document limits")
        driver.end(.lead, "<route>\(revised)</route>")
        #expect(driver.expedition.phase == .reviewing)
        #expect(driver.expedition.previousRoutes.count == 1)
        #expect(driver.expedition.route?.changedAssignments(since: driver.expedition.previousRoutes[0]) == ["stream"])
    }

    @Test func discardingTheRouteStops() throws {
        var driver = ExpeditionDriver()
        driver.send(.start)
        driver.end(.lead, "<route>\(ExpeditionDriver.twoLegs)</route>")
        driver.send(.discard)
        #expect(driver.expedition.phase == .stopped)
        driver.send(.approve(try #require(driver.expedition.route)))
        #expect(driver.expedition.approvedAt == nil)
    }

    @Test func failedCheckpointStartsFixRoundsInTheBuildersSessionThenEscalates() throws {
        var driver = ExpeditionDriver(settings: ExpeditionSettings(fixRounds: 1, consultsLeadBetweenLegs: false))
        driver.setOut()
        driver.end(.assignment("writer"), done)
        driver.end(.assignment("stream"), done)
        let reviewer = try #require(driver.tasks[.checkpoint("leg-1")])
        driver.end(.checkpoint("leg-1"), "Quoting breaks on newlines (Export.swift:12).\nVERDICT: changes - newline quoting")

        // The fix continues the last builder's session instead of starting a new one.
        let fix = try #require(driver.expedition.assignments(in: "leg-1").last)
        #expect(fix.isFix)
        #expect(fix.task == driver.tasks[.assignment("stream")])
        #expect(!driver.created.contains(.assignment(fix.id)))
        #expect(driver.lastPrompt?.text.contains("Quoting breaks on newlines") == true)
        driver.end(.assignment(fix.id), "Fixed.\nGOAL: complete - added a test")

        // The same reviewer session checks again.
        #expect(driver.expedition.checkpoint("leg-1")?.task == reviewer)
        #expect(driver.lastPrompt?.text.contains("addressed your findings") == true)
        driver.end(.checkpoint("leg-1"), "Still broken.\nVERDICT: changes - still breaks")
        guard case .blocked = driver.status(.checkpoint("leg-1")) else {
            Issue.record("The checkpoint should wait on the user after its rounds")
            return
        }
        #expect(driver.expedition.phase == .needsYou)

        driver.send(.anotherRound("leg-1"))
        let second = try #require(driver.expedition.assignments(in: "leg-1").last)
        #expect(second.id != fix.id)
        driver.end(.assignment(second.id), done)
        driver.end(.checkpoint("leg-1"), "VERDICT: changes - nitpicks")
        driver.send(.accept(.checkpoint("leg-1")))
        #expect(driver.status(.checkpoint("leg-1")) == .succeeded)
        #expect(driver.status(.assignment("button")) == .running)
    }

    @Test func aReviewerWithoutAVerdictIsRemindedOnce() {
        var driver = ExpeditionDriver()
        driver.setOut()
        driver.end(.assignment("writer"), done)
        driver.end(.assignment("stream"), done)
        driver.end(.checkpoint("leg-1"), "It's fine I guess.")
        #expect(driver.lastPrompt?.text.hasPrefix("Your last reply didn't end with a verdict line") == true)
        driver.end(.checkpoint("leg-1"), "Yes, fine.")
        guard case .blocked = driver.status(.checkpoint("leg-1")) else {
            Issue.record("Expected the checkpoint to wait on the user")
            return
        }
    }

    @Test func spentBudgetHoldsTheCrewBetweenTurnsUntilExtended() {
        var driver = ExpeditionDriver(budget: ExpeditionBudget(maxCost: 1))
        driver.setOut()
        driver.end(.assignment("writer"), "Halfway.\nGOAL: continuing - tests next", cost: 1.2)
        #expect(driver.status(.assignment("writer")) == .paused)
        #expect(driver.expedition.attention.contains { if case .budgetReached = $0.kind { true } else { false } })
        #expect(driver.expedition.phase == .needsYou)
        let sent = driver.prompts.count
        driver.send(.extendBudget)
        #expect(driver.prompts.count == sent + 1)
        #expect(driver.status(.assignment("writer")) == .running)
        #expect(driver.expedition.budget.maxCost == 2.2)
    }

    @Test func pauseLetsTheTurnFinishAndHoldsTheNextPrompt() {
        var driver = ExpeditionDriver()
        driver.setOut()
        driver.send(.pause)
        #expect(driver.expedition.phase == .paused)
        driver.end(.assignment("writer"), "Working.\nGOAL: continuing - more")
        #expect(driver.status(.assignment("writer")) == .paused)
        driver.send(.resume)
        #expect(driver.status(.assignment("writer")) == .running)
        #expect(driver.lastPrompt?.text.contains("<goal-continue") == true)
    }

    @Test func aCrashedTurnIsResumedOnceThenWaitsForTheUser() {
        var driver = ExpeditionDriver()
        driver.setOut()
        driver.end(.assignment("writer"), nil, outcome: .failed("Codex stopped unexpectedly"))
        #expect(driver.status(.assignment("writer")) == .running)
        #expect(driver.lastPrompt?.text.hasPrefix("Your previous turn failed: Codex stopped unexpectedly") == true)
        driver.end(.assignment("writer"), nil, outcome: .failed("Codex stopped unexpectedly"))
        #expect(driver.status(.assignment("writer")) == .failed("The turn failed: Codex stopped unexpectedly"))
        driver.send(.retry(.assignment("writer")))
        #expect(driver.created.filter { $0 == .assignment("writer") }.count == 2)
    }

    @Test func restoredAfterAQuitIsInterruptedAndResumesWithANote() throws {
        var driver = ExpeditionDriver()
        driver.setOut()
        let data = try JSONEncoder().encode(driver.expedition)
        driver.expedition = try JSONDecoder().decode(Expedition.self, from: data).restored()
        #expect(driver.status(.assignment("writer")) == .interrupted)
        #expect(driver.expedition.phase == .needsYou)
        #expect(driver.expedition.activeSince == nil)
        driver.send(.resumeSlot(.assignment("writer")))
        #expect(driver.status(.assignment("writer")) == .running)
        #expect(driver.lastPrompt?.text.hasPrefix("Your previous turn was cut off") == true)
    }

    @Test func stopCancelsRunningTurnsAndIgnoresLateResults() {
        var driver = ExpeditionDriver()
        driver.setOut()
        driver.send(.stop)
        #expect(driver.cancelled == [driver.tasks[.assignment("writer")]])
        #expect(driver.expedition.phase == .stopped)
        driver.end(.assignment("writer"), done)
        #expect(driver.status(.assignment("writer")) == .cancelled)
    }

    @Test func wrapUpSkipsWhatHasntStartedAndDebriefs() {
        var driver = ExpeditionDriver(settings: ExpeditionSettings(opensPullRequest: false))
        driver.setOut()
        driver.send(.wrapUp)
        #expect(driver.status(.assignment("stream")) == .skipped)
        driver.end(.assignment("writer"), done)
        #expect(driver.expedition.phase == .debriefing)
        #expect(driver.lastPrompt?.text.hasPrefix("The user asked to wrap up") == true)
        driver.end(.lead, "Partial debrief.")
        #expect(driver.expedition.phase == .complete)
        #expect(driver.pullRequests.isEmpty)
    }

    @Test func leadAdditionsApplyButRewritesWaitForTheUser() throws {
        var driver = ExpeditionDriver()
        driver.setOut()
        driver.end(.assignment("writer"), done)
        driver.end(.assignment("stream"), done)
        driver.end(.checkpoint("leg-1"), "VERDICT: pass")
        let added = """
            <route>{"legs": [{"title": "UI", "outcome": "Users can export from the toolbar.", "assignments": [
              {"id": "button", "title": "Wire the export button", "brief": "Toolbar button.", "doneWhen": ["Button exports"], "assignee": "codex", "after": ["stream"]},
              {"id": "docs", "title": "Document export", "brief": "README.", "doneWhen": ["README mentions CSV"], "assignee": "codex", "after": ["button"]}
            ]}]}</route>
            """
        driver.end(.lead, added)
        #expect(driver.expedition.pendingRouteChange == nil)
        #expect(driver.expedition.assignment("docs")?.status == .waiting)
        #expect(driver.status(.assignment("button")) == .running)

        // Rewriting approved work waits for the user, and the crew holds.
        var rewriting = ExpeditionDriver()
        rewriting.setOut()
        rewriting.end(.assignment("writer"), done)
        rewriting.end(.assignment("stream"), done)
        rewriting.end(.checkpoint("leg-1"), "VERDICT: pass")
        rewriting.end(.lead, added.replacingOccurrences(of: "Toolbar button.", with: "Menu item instead."))
        #expect(rewriting.expedition.pendingRouteChange != nil)
        #expect(rewriting.expedition.phase == .needsYou)
        #expect(rewriting.status(.assignment("button")) == .waiting)
        rewriting.send(.approveRouteChange)
        #expect(rewriting.expedition.assignment("button")?.assignment.brief == "Menu item instead.")
        #expect(rewriting.status(.assignment("button")) == .running)
    }

    @Test func aProviderLimitResumesAtTheReset() {
        var driver = ExpeditionDriver()
        driver.setOut()
        driver.end(.assignment("writer"), nil, outcome: .limited("Codex · 5-hour limit reached · resets 3:05 PM"))
        #expect(driver.expedition.phase == .limited)
        #expect(driver.expedition.attention.allSatisfy { $0.isLimit })
        driver.send(.limitReset(.assignment("writer")))
        #expect(driver.status(.assignment("writer")) == .running)
    }

    @Test func blockedBuilderPicksBackUpWithTheUsersReply() {
        var driver = ExpeditionDriver()
        driver.setOut()
        driver.end(.assignment("writer"), "Which delimiter?\nGOAL: blocked - comma or semicolon?")
        #expect(driver.status(.assignment("writer")) == .blocked("comma or semicolon?"))
        driver.send(.message(.assignment("writer"), text: "Comma."))
        #expect(driver.status(.assignment("writer")) == .running)
        #expect(driver.lastPrompt?.text == "Comma.")
        // While it works, a message is steered in, not sent as a prompt.
        driver.send(.message(.assignment("writer"), text: "Also handle tabs."))
        #expect(driver.messages.last?.text == "Also handle tabs.")
    }

    @Test func reassigningMovesWorkToAnotherAgent() {
        var driver = ExpeditionDriver()
        driver.setOut()
        driver.end(.assignment("writer"), nil, outcome: .refused)
        driver.end(.assignment("writer"), nil, outcome: .refused)
        driver.send(.reassign("writer", agent: ExpeditionDriver.claude))
        #expect(driver.expedition.assignment("writer")?.assignment.assignee == "claude-code")
        #expect(driver.expedition.crew.builders.contains(ExpeditionDriver.claude))
        #expect(driver.status(.assignment("writer")) == .running)
    }

    @Test func activeTimeCountsOnlyWhileSomeoneWorks() {
        var driver = ExpeditionDriver(budget: ExpeditionBudget(maxDuration: 60))
        driver.setOut()
        driver.clock += 120
        driver.end(.assignment("writer"), "More.\nGOAL: continuing - next")
        #expect(driver.status(.assignment("writer")) == .paused)
        #expect(driver.expedition.exhaustedBudget(at: driver.clock) == "Used the 1m time budget")
    }
}
