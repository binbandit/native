import Foundation
import Testing
@testable import NativeAutomation

@MainActor
final class FakeGoalHost: GoalHost {
    var canSendGoalPrompt = true
    var goalSessionCost: Double?
    var goalLatestReply: String?
    var sent: [String] = []
    var sendError: (any Error)?

    func sendGoalPrompt(_ text: String) async throws {
        if let sendError { throw sendError }
        sent.append(text)
    }
}

@MainActor
@Suite struct GoalControllerTests {
    @Test func setSendsTheKickoffAndContinuesAfterEachTurn() async {
        let host = FakeGoalHost()
        let controller = GoalController(store: nil, storageKey: nil)
        controller.host = host
        await controller.set(objective: "Ship it", budget: GoalBudget(maxIterations: 3))
        #expect(host.sent.count == 1)
        controller.turnWillStart(.goal)
        host.goalLatestReply = "Working.\nGOAL: continuing - tests"
        await controller.turnDidEnd(.ended)
        #expect(host.sent.count == 2)
        #expect(controller.goal?.lastReason == "tests")
    }

    @Test func aPromptThatCantGoOutPausesTheGoalWithTheReason() async {
        struct Gone: LocalizedError { var errorDescription: String? { "The agent is no longer running." } }
        let host = FakeGoalHost()
        host.sendError = Gone()
        let controller = GoalController(store: nil, storageKey: nil)
        controller.host = host
        await controller.set(objective: "Ship it", budget: .unlimited)
        #expect(controller.goal?.status == .paused)
        #expect(controller.goal?.lastReason == "Couldn't send the next prompt: The agent is no longer running.")
    }

    @Test func queuedUserMessagesGoFirst() async {
        let host = FakeGoalHost()
        let controller = GoalController(store: nil, storageKey: nil)
        controller.host = host
        await controller.set(objective: "x", budget: .unlimited)
        controller.turnWillStart(.goal)
        host.canSendGoalPrompt = false
        await controller.turnDidEnd(.ended)
        #expect(host.sent.count == 1)
        host.canSendGoalPrompt = true
        controller.turnWillStart(.user)
        await controller.turnDidEnd(.ended)
        #expect(host.sent.count == 2)
    }

    @Test func goalCommandsDriveTheController() async {
        let host = FakeGoalHost()
        let controller = GoalController(store: nil, storageKey: nil)
        controller.host = host
        await controller.perform(.set(objective: "First"))
        await controller.perform(.pause)
        #expect(controller.goal?.status == .paused)
        await controller.perform(.edit)
        #expect(controller.isEditorRequested)
        await controller.perform(.clear)
        #expect(controller.goal == nil)
    }

    @Test func goalsPersistAndComeBackPaused() async throws {
        let url = FileManager.default.temporaryDirectory.appending(path: "goals-\(UUID()).json")
        let store = GoalStore(url: url)
        let controller = GoalController(store: store, storageKey: "codex/s1")
        controller.host = FakeGoalHost()
        await controller.set(objective: "Persist me", budget: GoalBudget(maxCost: 2))
        let reopened = GoalController(store: GoalStore(url: url), storageKey: "codex/s1")
        #expect(reopened.goal?.objective == "Persist me")
        #expect(reopened.goal?.status == .paused)
        #expect(reopened.goal?.budget.maxCost == 2)
    }
}

@MainActor
final class FakeWorkflowHost: WorkflowHost {
    var workflowAgents = [WorkflowAgent(id: "claude-code", name: "Claude Code"), WorkflowAgent(id: "codex", name: "Codex")]
    var defaultWorkflowAgent: WorkflowAgent.ID? = "claude-code"
    var created: [(agent: String, title: String)] = []
    var prompts: [UUID: [String]] = [:]
    var replies: [UUID: String] = [:]
    var failCreation = false

    func createStepTask(agent: WorkflowAgent.ID, title: String, cwd: URL) async throws -> UUID {
        if failCreation { throw CocoaError(.fileNoSuchFile) }
        created.append((agent, title))
        return UUID()
    }

    func sendToStepTask(_ task: UUID, text: String) async throws {
        prompts[task, default: []].append(text)
    }

    func cancelStepTask(_ task: UUID) async {}

    func stepTaskReport(_ task: UUID) -> WorkflowTaskReport? {
        WorkflowTaskReport(reply: replies[task], cost: nil)
    }

    func openPullRequest(_ draft: WorkflowPullRequestDraft) async throws -> WorkflowPullRequestResult {
        WorkflowPullRequestResult(url: URL(filePath: "/pr"))
    }

    func runScript(_ source: String, input: String, cwd: URL) async throws -> String {
        "script(\(input))"
    }
}

@MainActor
@Suite struct WorkflowRunnerTests {
    /// Lets the runner's effect tasks run.
    func settle() async {
        for _ in 0..<20 { await Task.yield() }
    }

    @Test func runsStepsThroughTheHost() async throws {
        let host = FakeWorkflowHost()
        let runner = WorkflowRunner()
        runner.host = host
        let definition = try #require(BuiltInWorkflows.all.first { $0.id == "plan-implement-review" })
        let id = runner.start(definition, input: "Add CSV export", cwd: URL(filePath: "/work/app"))
        await settle()
        #expect(host.created.map(\.agent) == ["claude-code"])
        #expect(host.created.first?.title == "Plan: Add CSV export")
        let planTask = try #require(runner.run(id)?.stepRun("plan")?.task)
        #expect(host.prompts[planTask]?.count == 1)

        host.replies[planTask] = "The plan"
        runner.turnEnded(task: planTask, outcome: .ended)
        #expect(runner.run(id)?.stepRun("implement")?.status == .awaitingApproval)
        runner.turnEnded(task: UUID(), outcome: .ended)
        #expect(runner.run(id)?.stepRun("plan")?.output == "The plan")
    }

    @Test func scriptStepsRunThroughTheHost() async throws {
        let host = FakeWorkflowHost()
        let runner = WorkflowRunner()
        runner.host = host
        let definition = WorkflowDefinition(id: "w", name: "W", summary: "", steps: [
            WorkflowStep(id: "count", title: "Count", kind: .script, prompt: "{{input}}", script: "export default (input) => input.length"),
        ])
        #expect(WorkflowIssue.find(in: definition) == [])
        let id = runner.start(definition, input: "abc", cwd: URL(filePath: "/"))
        await settle()
        #expect(runner.run(id)?.stepRun("count")?.output == "script(abc)")
        #expect(runner.run(id)?.phase == .succeeded)
    }

    @Test func creationFailuresSurfaceOnTheStep() async throws {
        let host = FakeWorkflowHost()
        host.failCreation = true
        let runner = WorkflowRunner()
        runner.host = host
        let definition = WorkflowDefinition(id: "w", name: "W", summary: "", steps: [WorkflowStep(id: "a", title: "A", prompt: "a")])
        let id = runner.start(definition, input: "", cwd: URL(filePath: "/"))
        await settle()
        guard case .failed(let message)? = runner.run(id)?.stepRun("a")?.status else {
            Issue.record("expected a failed step")
            return
        }
        #expect(message.hasPrefix("Couldn't start Claude Code"))
        #expect(runner.run(id)?.phase == .halted)
    }
}
