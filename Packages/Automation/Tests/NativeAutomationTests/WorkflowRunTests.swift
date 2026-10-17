import Foundation
import Testing
@testable import NativeAutomation

/// Drives a run the way `WorkflowRunner` does: creates tasks right away and records prompts.
struct RunDriver {
    var run: WorkflowRun
    var clock = Date(timeIntervalSince1970: 1_000_000)
    var tasks: [String: UUID] = [:]
    var prompts: [(step: String, text: String)] = []
    var cancelled: [UUID] = []
    var pullRequests: [WorkflowPullRequestDraft] = []

    static let claude = WorkflowAgent(id: "claude-code", name: "Claude Code")
    static let codex = WorkflowAgent(id: "codex", name: "Codex")

    init(_ definition: WorkflowDefinition, input: String = "Add CSV export", agents: [WorkflowAgent] = [claude, codex]) {
        let assignments = WorkflowAssignment.resolve(definition, agents: agents, defaultAgent: agents.first?.id)
        run = WorkflowRun(definition: definition, input: input, cwd: URL(filePath: "/work/app"), assignments: assignments, at: clock)
    }

    mutating func send(_ event: WorkflowEvent) {
        clock += 10
        var pending = run.handle(event, at: clock)
        while !pending.isEmpty {
            let effect = pending.removeFirst()
            switch effect {
            case .createTask(let step, _, _):
                let task = UUID()
                tasks[step] = task
                clock += 1
                pending += run.handle(.taskCreated(step: step, task: task), at: clock)
            case .prompt(let step, _, let text):
                prompts.append((step, text))
            case .cancelTask(let task):
                cancelled.append(task)
            case .openPullRequest(_, let draft):
                pullRequests.append(draft)
            case .runScript(let step, _, let input, _):
                pending += run.handle(.scriptFinished(step: step, output: input), at: clock)
            }
        }
    }

    mutating func end(_ step: String, _ reply: String?, outcome: TurnOutcome = .ended, cost: Double? = nil) {
        send(.turnEnded(step: step, outcome: outcome, reply: reply, cost: cost))
    }

    func status(_ step: String) -> WorkflowStepStatus? {
        run.stepRun(step)?.status
    }
}

@Suite struct WorkflowRunTests {
    func builtIn(_ id: String) throws -> WorkflowDefinition {
        try #require(BuiltInWorkflows.all.first { $0.id == id })
    }

    @Test func planImplementReviewEndToEnd() throws {
        var driver = RunDriver(try builtIn("plan-implement-review"))
        driver.send(.start)
        #expect(driver.status("plan") == .running)
        #expect(driver.prompts.last?.text.contains("Add CSV export") == true)

        driver.end("plan", "1. Add exporter\n2. Test it")
        #expect(driver.status("implement") == .awaitingApproval)
        #expect(driver.run.phase == .awaitingApproval)
        #expect(driver.run.stepRun("implement")?.prompt?.contains("1. Add exporter") == true)
        #expect(driver.run.oldestRequest?.id == "implement")

        driver.send(.approve(step: "implement", prompt: nil))
        let kickoff = try #require(driver.prompts.last)
        #expect(kickoff.step == "implement")
        #expect(GoalPrompt(parsing: kickoff.text) != nil)
        #expect(driver.run.stepRun("implement")?.assignment.agent == RunDriver.codex)

        driver.end("implement", "Wrote it.\nGOAL: continuing - tests next")
        #expect(driver.status("implement") == .running)
        #expect(driver.prompts.count == 3)
        driver.end("implement", "Added CSV export; tests pass.\nGOAL: complete - swift test passed")
        #expect(driver.status("implement") == .succeeded)
        #expect(driver.run.stepRun("implement")?.output == "Added CSV export; tests pass.")

        let review = try #require(driver.prompts.last)
        #expect(review.step == "review")
        #expect(review.text.contains("Codex summarized the work as:\n\nAdded CSV export; tests pass."))
        driver.end("review", "Ready.")
        #expect(driver.run.phase == .succeeded)
        #expect(driver.run.endedAt != nil)
    }

    @Test func parallelStepsStartTogether() {
        let definition = WorkflowDefinition(id: "w", name: "W", summary: "", steps: [
            WorkflowStep(id: "a", title: "A", prompt: "a"),
            WorkflowStep(id: "b", title: "B", prompt: "b", after: []),
            WorkflowStep(id: "c", title: "C", prompt: "{{steps.a.output}} {{steps.b.output}}", after: ["a", "b"]),
        ])
        var driver = RunDriver(definition)
        driver.send(.start)
        #expect(driver.status("a") == .running)
        #expect(driver.status("b") == .running)
        driver.end("b", "B done")
        #expect(driver.status("c") == .waiting)
        driver.end("a", "A done")
        #expect(driver.prompts.last?.step == "c")
        #expect(driver.prompts.last?.text == "A done B done")
    }

    @Test func failedStepHoldsOnlyItsDependentsAndOffersRetrySkip() {
        let definition = WorkflowDefinition(id: "w", name: "W", summary: "", steps: [
            WorkflowStep(id: "a", title: "A", prompt: "a"),
            WorkflowStep(id: "b", title: "B", prompt: "b", after: []),
            WorkflowStep(id: "c", title: "C", prompt: "c", after: ["a"]),
        ])
        var driver = RunDriver(definition)
        driver.send(.start)
        driver.end("a", nil, outcome: .failed("Agent crashed"))
        #expect(driver.status("a") == .failed("Agent crashed"))
        #expect(driver.run.phase == .running)
        driver.end("b", "ok")
        #expect(driver.run.phase == .halted)

        let firstTask = driver.tasks["a"]
        driver.send(.retry(step: "a"))
        #expect(driver.status("a") == .running)
        #expect(driver.tasks["a"] != firstTask)
        driver.end("a", nil, outcome: .failed("Again"))
        driver.send(.skip(step: "a"))
        #expect(driver.status("a") == .skipped)
        #expect(driver.status("c") == .running)
    }

    @Test func cancelledTurnStopsTheStepAndResumeContinuesInItsTask() {
        let definition = WorkflowDefinition(id: "w", name: "W", summary: "", steps: [WorkflowStep(id: "a", title: "A", prompt: "a")])
        var driver = RunDriver(definition)
        driver.send(.start)
        driver.send(.stop(step: "a"))
        #expect(driver.cancelled == [driver.tasks["a"]].compactMap(\.self))
        driver.end("a", "partial", outcome: .cancelled)
        #expect(driver.status("a") == .cancelled)
        driver.send(.resume(step: "a"))
        #expect(driver.prompts.last?.text == WorkflowRun.continuePrompt)
        driver.end("a", "finished")
        #expect(driver.run.phase == .succeeded)
    }

    @Test func blockedGoalStepResumesOnReply() throws {
        var driver = RunDriver(try builtIn("implement-cross-review"))
        driver.send(.start)
        driver.end("implement", "Which database?\nGOAL: blocked - which database should I use?")
        #expect(driver.status("implement") == .blocked("which database should I use?"))
        #expect(driver.run.phase == .blocked)
        driver.send(.reply(step: "implement", text: "Postgres"))
        #expect(driver.prompts.last?.text == "Postgres")
        #expect(driver.status("implement") == .running)
        driver.end("implement", "Done\nGOAL: complete - tests pass")
        #expect(driver.status("review") == .running)
    }

    @Test func continuesReusesTheEarlierTask() throws {
        var driver = RunDriver(try builtIn("implement-cross-review"))
        driver.send(.start)
        driver.end("implement", "Implemented.\nGOAL: complete - verified", cost: 0.5)
        driver.end("review", "Needs changes: missing test", cost: 0.2)
        #expect(driver.status("address") == .awaitingApproval)
        driver.send(.approve(step: "address", prompt: nil))
        #expect(driver.run.stepRun("address")?.task == driver.tasks["implement"])
        #expect(driver.prompts.last?.step == "address")
        #expect(driver.prompts.last?.text.contains("Needs changes: missing test") == true)
        driver.end("address", "Fixed.\nGOAL: complete - added test", cost: 0.8)
        #expect(abs((driver.run.stepRun("address")?.cost ?? 0) - 0.3) < 0.0001)
        #expect(abs((driver.run.cost ?? 0) - 1.0) < 0.0001)
        #expect(driver.run.phase == .succeeded)
    }

    @Test func goalBudgetLimitsAStepAndResumeGrantsMore() {
        let definition = WorkflowDefinition(id: "w", name: "W", summary: "", steps: [
            WorkflowStep(id: "a", title: "A", prompt: "a", goal: GoalBudget(maxIterations: 1)),
        ])
        var driver = RunDriver(definition)
        driver.send(.start)
        driver.end("a", "GOAL: continuing - more to do")
        #expect(driver.status("a") == .limited("Used all 1 iteration"))
        driver.send(.resume(step: "a"))
        #expect(driver.status("a") == .running)
        #expect(driver.run.stepRun("a")?.goal?.goal.budget.maxIterations == 2)
    }

    @Test func providerLimitIsLimitedNotRetried() {
        let definition = WorkflowDefinition(id: "w", name: "W", summary: "", steps: [WorkflowStep(id: "a", title: "A", prompt: "a", goal: GoalBudget(maxIterations: 5))])
        var driver = RunDriver(definition)
        driver.send(.start)
        driver.end("a", nil, outcome: .limited("5-hour limit reached · resets 3:05 PM"))
        #expect(driver.status("a") == .limited("5-hour limit reached · resets 3:05 PM"))
        #expect(driver.prompts.count == 1)
    }

    @Test func rejectingAGateCancelsTheRun() throws {
        var driver = RunDriver(try builtIn("plan-implement-review"))
        driver.send(.start)
        driver.end("plan", "plan")
        driver.send(.reject(step: "implement"))
        #expect(driver.run.phase == .cancelled)
        #expect(driver.status("implement") == .cancelled)
        #expect(driver.status("review") == .cancelled)
    }

    @Test func cancelStopsRunningTasks() {
        let definition = WorkflowDefinition(id: "w", name: "W", summary: "", steps: [
            WorkflowStep(id: "a", title: "A", prompt: "a"),
            WorkflowStep(id: "b", title: "B", prompt: "b"),
        ])
        var driver = RunDriver(definition)
        driver.send(.start)
        driver.send(.cancel)
        #expect(driver.cancelled.count == 1)
        #expect(driver.status("b") == .cancelled)
        driver.end("a", "late", outcome: .cancelled)
        #expect(driver.status("a") == .cancelled)
        driver.send(.retry(step: "a"))
        #expect(driver.status("a") == .cancelled)
    }

    @Test func pauseHoldsNewWorkAndResumeReleasesIt() {
        let definition = WorkflowDefinition(id: "w", name: "W", summary: "", steps: [
            WorkflowStep(id: "a", title: "A", prompt: "a", goal: GoalBudget(maxIterations: 5)),
            WorkflowStep(id: "b", title: "B", prompt: "b"),
        ])
        var driver = RunDriver(definition)
        driver.send(.start)
        driver.send(.pauseRun)
        #expect(driver.run.phase == .paused)
        driver.end("a", "GOAL: continuing - next")
        #expect(driver.status("a") == .paused)
        #expect(driver.prompts.count == 1)
        driver.send(.resumeRun)
        #expect(driver.status("a") == .running)
        #expect(driver.prompts.count == 2)
        driver.send(.pauseRun)
        driver.end("a", "GOAL: complete - done")
        #expect(driver.status("b") == .waiting)
        driver.send(.resumeRun)
        #expect(driver.status("b") == .running)
    }

    @Test func pullRequestStepOpensFromRenderedTemplates() throws {
        var driver = RunDriver(try builtIn("ship-pull-request"))
        driver.send(.start)
        driver.end("plan", "plan")
        driver.send(.approve(step: "implement", prompt: "Edited prompt"))
        #expect(driver.run.stepRun("implement")?.goal?.goal.objective == "Edited prompt")
        driver.end("implement", "Adds CSV export.\nGOAL: complete - committed")
        driver.end("review", "Ready.")
        driver.end("address", "Nothing to fix.\nGOAL: complete - none")
        #expect(driver.status("pull-request") == .awaitingApproval)
        driver.send(.approve(step: "pull-request", prompt: nil))
        let draft = try #require(driver.pullRequests.first)
        #expect(draft.title == "Add CSV export")
        #expect(draft.body.hasPrefix("Adds CSV export."))
        #expect(draft.body.contains("cross-reviewed (Claude Code)"))
        driver.send(.pullRequestOpened(step: "pull-request", WorkflowPullRequestResult(url: URL(string: "https://github.com/o/r/pull/7")!, number: 7)))
        #expect(driver.run.phase == .succeeded)
        #expect(driver.run.stepRun("pull-request")?.output == "https://github.com/o/r/pull/7")
    }

    @Test func eventsAndEffectsRoundTripThroughJSON() throws {
        let events: [WorkflowEvent] = [
            .turnEnded(step: "a", outcome: .limited("5-hour limit"), reply: "r", cost: 1.5),
            .approve(step: "a", prompt: nil), .reply(step: "a", text: "Postgres"), .pauseRun, .cancel,
        ]
        #expect(try JSONDecoder().decode([WorkflowEvent].self, from: JSONEncoder().encode(events)) == events)
        let effects: [WorkflowEffect] = [.createTask(step: "a", agent: RunDriver.codex, title: "A"), .cancelTask(UUID())]
        #expect(try JSONDecoder().decode([WorkflowEffect].self, from: JSONEncoder().encode(effects)) == effects)
    }

    @Test func scriptStepsNeedASource() {
        let definition = WorkflowDefinition(id: "w", name: "W", summary: "", steps: [
            WorkflowStep(id: "s", title: "S", kind: .script, agent: .agent("codex"), prompt: "x"),
        ])
        #expect(WorkflowIssue.find(in: definition).count == 2)
    }

    @Test func runsComeBackInterruptedAndResumeInTheSameTask() async throws {
        var driver = RunDriver(try builtIn("implement-cross-review"))
        driver.send(.start)
        let task = driver.tasks["implement"]
        let url = FileManager.default.temporaryDirectory.appending(path: "runs-\(UUID()).json")
        await MainActor.run { WorkflowRunStore(url: url).save([driver.run]) }
        let restored = try #require(await MainActor.run { WorkflowRunStore(url: url).load() }.first)
        #expect(restored.stepRun("implement")?.status == .interrupted)
        #expect(restored.stepRun("implement")?.goal?.goal.status == .paused)
        #expect(restored.phase == .halted)

        driver.run = restored
        driver.send(.resume(step: "implement"))
        #expect(driver.status("implement") == .running)
        #expect(driver.run.stepRun("implement")?.task == task)
        #expect(driver.prompts.last?.text.contains("Pick the goal back up") == true)
        driver.end("implement", "Done\nGOAL: complete - tests pass")
        #expect(driver.status("review") == .running)
    }

    @Test func plainStepsResumeWithTheInterruptionExplained() {
        let definition = WorkflowDefinition(id: "w", name: "W", summary: "", steps: [WorkflowStep(id: "a", title: "A", prompt: "a")])
        var driver = RunDriver(definition)
        driver.send(.start)
        driver.run = driver.run.restored()
        driver.send(.resume(step: "a"))
        #expect(driver.prompts.last?.text == WorkflowRun.interruptedPrompt)
    }

    @Test func runRoundTripsThroughJSON() throws {
        var driver = RunDriver(try builtIn("plan-implement-review"))
        driver.send(.start)
        driver.end("plan", "plan")
        let data = try JSONEncoder().encode(driver.run)
        #expect(try JSONDecoder().decode(WorkflowRun.self, from: data) == driver.run)
    }
}
