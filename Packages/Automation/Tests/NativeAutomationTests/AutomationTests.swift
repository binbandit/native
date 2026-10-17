import Foundation
import Testing
@testable import NativeAutomation

@Suite struct AutomationScheduleTests {
    var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Los_Angeles") ?? .gmt
        return calendar
    }

    func date(_ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour, minute: minute)) ?? .now
    }

    @Test func dailyAndWeeklyFireAtTheirTime() {
        #expect(AutomationSchedule.daily(hour: 9, minute: 0).nextFire(after: date(17, 8), anchor: date(1, 0), calendar: calendar) == date(17, 9))
        #expect(AutomationSchedule.daily(hour: 9, minute: 0).nextFire(after: date(17, 9), anchor: date(1, 0), calendar: calendar) == date(18, 9))
        // Oct 17, 2026 is a Saturday; the next Monday is the 19th.
        #expect(AutomationSchedule.weekly(weekday: 2, hour: 9, minute: 30).nextFire(after: date(17, 12), anchor: date(1, 0), calendar: calendar) == date(19, 9, 30))
    }

    @Test func intervalsKeepTheirRhythm() {
        let schedule = AutomationSchedule.everyHours(4)
        #expect(schedule.nextFire(after: date(17, 9, 10), anchor: date(17, 8), calendar: calendar) == date(17, 12))
        #expect(schedule.nextFire(after: date(17, 12), anchor: date(17, 8), calendar: calendar) == date(17, 16))
        #expect(AutomationSchedule.everyHours(1).summary(calendar: calendar) == "Every hour")
    }

    @Test func plannerRunsOnceAndMarksMissedTimes() {
        let automation = Automation(name: "Morning", triggers: [.schedule(.daily(hour: 9, minute: 0)), .schedule(.everyHours(1))], action: .prompt("x"), project: URL(filePath: "/p"), createdAt: date(17, 6))
        let onTime = AutomationPlanner.due([automation], lastChecked: [automation.id: date(17, 8, 30)], now: date(17, 9, 1))
        #expect(onTime.count == 1)
        #expect(onTime.first.map { if case .scheduled = $0.1 { true } else { false } } == true)
        let late = AutomationPlanner.due([automation], lastChecked: [automation.id: date(16, 9, 1)], now: date(17, 14))
        #expect(late.count == 1)
        #expect(late.first.map { if case .missed = $0.1 { true } else { false } } == true)
        var paused = automation
        paused.isPaused = true
        #expect(AutomationPlanner.due([paused], lastChecked: [:], now: date(18, 14)).isEmpty)
    }
}

@Suite struct AutomationEventTests {
    func snapshot(_ number: Int, updated: TimeInterval, authored: Bool = true, review: Bool = false, failing: Bool = false) -> PullRequestSnapshot {
        PullRequestSnapshot(
            url: URL(string: "https://github.com/acme/app/pull/\(number)") ?? URL(filePath: "/"), repository: "acme/app", number: number,
            title: "PR \(number)", updatedAt: Date(timeIntervalSince1970: updated), isAuthored: authored, isReviewRequested: review, hasFailingChecks: failing
        )
    }

    @Test func firstPollIsABaseline() {
        #expect(AutomationEventDetector.occurrences(from: nil, to: [snapshot(1, updated: 1)], at: .now).isEmpty)
    }

    @Test func changesBecomeEvents() {
        let before = [snapshot(1, updated: 1), snapshot(2, updated: 1, authored: false)]
        let after = [snapshot(1, updated: 5, failing: true), snapshot(2, updated: 1, authored: false, review: true), snapshot(3, updated: 2)]
        let kinds = AutomationEventDetector.occurrences(from: before, to: after, at: .now).map(\.kind)
        #expect(kinds == [.pullRequestUpdated, .checksFailed, .reviewRequested, .pullRequestOpened])
    }

    @Test func automationsMatchTheirRepositoryOrProject() {
        let automation = Automation(name: "CI", triggers: [.event(.checksFailed), .event(.taskFinished)], action: .prompt("fix"), project: URL(filePath: "/work/app"), repository: "Acme/App", createdAt: .now)
        let ci = AutomationOccurrence(kind: .checksFailed, key: "k", repository: "acme/app", subject: "s", occurredAt: .now)
        let other = AutomationOccurrence(kind: .checksFailed, key: "k", repository: "acme/web", subject: "s", occurredAt: .now)
        let task = AutomationOccurrence(kind: .taskFinished, key: "t", project: URL(filePath: "/work/app/"), subject: "s", occurredAt: .now)
        #expect(automation.matches(ci))
        #expect(!automation.matches(other))
        #expect(automation.matches(task))
    }
}

@MainActor
final class FakeAutomationHost: AutomationHost {
    let runner = WorkflowRunner()
    var automationAgents = [WorkflowAgent(id: "codex", name: "Codex")]
    var workflowLibrary = WorkflowLibrary()
    var snapshots: [PullRequestSnapshot] = []
    var snapshotError: (any Error)?
    var started: [(input: String, overrides: [String: String])] = []
    var failWorkspace = false

    init() {
        runner.host = FakeWorkflowHost()
    }

    func repository(of project: URL) async -> String? { "acme/app" }

    func prepareWorkspace(for automation: Automation, title: String) async throws -> URL {
        if failWorkspace { throw CocoaError(.fileWriteNoPermission) }
        return automation.project
    }

    func startWorkflow(_ definition: WorkflowDefinition, input: String, cwd: URL, overrides: [String: WorkflowAgent.ID]) -> WorkflowRun.ID {
        started.append((input, overrides))
        return runner.start(definition, input: input, cwd: cwd, overrides: overrides)
    }

    func cancelWorkflowRun(_ id: WorkflowRun.ID) { runner.send(.cancel, to: id) }
    func workflowRun(_ id: WorkflowRun.ID) -> WorkflowRun? { runner.run(id) }
    func pullRequestSnapshots() async throws -> [PullRequestSnapshot] {
        if let snapshotError { throw snapshotError }
        return snapshots
    }
}

@MainActor
@Suite struct AutomationEngineTests {
    func settle() async {
        for _ in 0..<30 { await Task.yield() }
    }

    @Test func runNowStartsAWorkflowAndFollowsItToTheEnd() async throws {
        let host = FakeAutomationHost()
        let engine = AutomationEngine()
        host.runner.onRunChange = { engine.workflowRunChanged($0) }
        engine.host = host
        let automation = Automation(name: "Check deps", triggers: [], action: .prompt("Check for outdated dependencies"), agent: "codex", project: URL(filePath: "/work/app"), createdAt: .now)
        await engine.save(automation)
        #expect(engine.automations.first?.repository == "acme/app")
        engine.runNow(automation.id)
        await settle()
        #expect(host.started.first?.overrides == ["run": "codex"])
        var run = try #require(engine.runs(of: automation.id).first)
        #expect(run.status == .running)

        let workflow = try #require(run.workflowRun.flatMap(host.runner.run))
        let task = try #require(workflow.stepRun("run")?.task)
        (host.runner.host as? FakeWorkflowHost)?.replies[task] = "All up to date.\nMore detail"
        host.runner.turnEnded(task: task, outcome: .ended)
        run = try #require(engine.runs(of: automation.id).first)
        #expect(run.status == .succeeded)
        #expect(run.summary == "All up to date.")
    }

    @Test func overlappingTriggersAreSkippedNotStacked() async {
        let host = FakeAutomationHost()
        let engine = AutomationEngine()
        engine.host = host
        let automation = Automation(name: "A", triggers: [], action: .prompt("x"), project: URL(filePath: "/p"), createdAt: .now)
        await engine.save(automation)
        engine.runNow(automation.id)
        engine.runNow(automation.id)
        await settle()
        #expect(engine.runs(of: automation.id).map(\.status.label) == ["Skipped", "Running"])
    }

    @Test func eventsStartMatchingAutomationsOnce() async {
        let host = FakeAutomationHost()
        let engine = AutomationEngine()
        engine.host = host
        let automation = Automation(name: "Fix CI", triggers: [.event(.checksFailed)], action: .goal(objective: "Make CI pass", budget: GoalBudget(maxIterations: 3)), project: URL(filePath: "/p"), createdAt: .now)
        await engine.save(automation)
        let event = AutomationOccurrence(kind: .checksFailed, key: "ci:1", repository: "acme/app", subject: "acme/app#1 Fix", url: URL(string: "https://github.com/acme/app/pull/1"), occurredAt: .now)
        engine.ingest([event])
        engine.ingest([event])
        await settle()
        #expect(engine.runs(of: automation.id).count == 1)
        #expect(host.started.first?.input.hasPrefix("Make CI pass\n\nTriggered by: CI failed: acme/app#1 Fix") == true)
    }

    @Test func failuresToStartAreExplained() async {
        let host = FakeAutomationHost()
        host.failWorkspace = true
        let engine = AutomationEngine()
        engine.host = host
        let automation = Automation(name: "A", triggers: [], action: .workflow(id: "plan-implement-review", input: "x"), project: URL(filePath: "/p"), createdAt: .now)
        await engine.save(automation)
        engine.runNow(automation.id)
        await settle()
        guard case .failed(let message)? = engine.runs(of: automation.id).first?.status else {
            Issue.record("expected a failed run")
            return
        }
        #expect(!message.isEmpty)
    }

    @Test func anUnreadableEventSourceSaysWhy() async {
        let host = FakeAutomationHost()
        host.snapshotError = CocoaError(.fileReadNoPermission)
        let engine = AutomationEngine()
        engine.host = host
        engine.isEnabled = true
        await engine.save(Automation(name: "CI", triggers: [.event(.checksFailed)], action: .prompt("x"), project: URL(filePath: "/p"), createdAt: .now))
        await engine.tick()
        #expect(engine.needsPolling)
        #expect(engine.eventSourceProblem != nil)
    }

    @Test func stateRoundTripsThroughTheStore() async throws {
        let url = FileManager.default.temporaryDirectory.appending(path: "automations-\(UUID()).json")
        let engine = AutomationEngine(store: AutomationStore(url: url))
        let automation = Automation(name: "Weekly", triggers: [.schedule(.weekly(weekday: 2, hour: 9, minute: 0))], action: .prompt("x"), project: URL(filePath: "/p"), createdAt: .now)
        await engine.save(automation)
        let reopened = AutomationEngine(store: AutomationStore(url: url))
        #expect(reopened.automations == engine.automations)
    }
}
