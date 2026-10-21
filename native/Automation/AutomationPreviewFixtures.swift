#if NATIVE_PREVIEWS_WIP
import Foundation
import NativeAutomation

/// Goals, workflow runs and automations for previews, built as values so nothing runs: steps carry
/// the statuses a real run reaches, set directly instead of by driving agents.
enum AutomationPreviewFixtures {
    static let now = Date.now
    static let project = URL(filePath: "/Users/preview/Developer/native", directoryHint: .isDirectory)

    static let agents = [
        WorkflowAgent(id: "claude-code", name: "Claude Code", symbol: "asterisk"),
        WorkflowAgent(id: "codex", name: "Codex", symbol: "terminal"),
    ]

    static let library = WorkflowLibrary()

    /// Native's own workflows, then a plugin's: one that's fine and one whose id clashes.
    static let libraryWithPlugin = WorkflowLibrary(contributions: [
        (plugin: "release-tools", workflows: Array(BuiltInWorkflows.all.prefix(1)))
    ])

    /// Plan, implement, review: Native's first built-in workflow.
    static let definition: WorkflowDefinition? = BuiltInWorkflows.all.first

    static func assignments(for definition: WorkflowDefinition) -> [String: WorkflowAssignment] {
        WorkflowAssignment.resolve(definition, agents: agents, defaultAgent: "claude-code")
    }

    /// A run of `definition` with each step at the status given, in step order; steps past the list wait.
    static func run(
        _ input: String, statuses: [WorkflowStepStatus], minutesAgo: Double = 12,
        definition: WorkflowDefinition? = definition
    ) -> WorkflowRun? {
        guard let definition else { return nil }
        let started = now.addingTimeInterval(-minutesAgo * 60)
        var run = WorkflowRun(
            definition: definition, input: input, cwd: project, assignments: assignments(for: definition),
            at: started)
        for (index, status) in statuses.enumerated() where run.steps.indices.contains(index) {
            run.steps[index].status = status
            run.steps[index].startedAt = started.addingTimeInterval(Double(index) * 240)
            if status != .waiting, status != .awaitingApproval {
                run.steps[index].task = UUID()
                run.steps[index].turns = index + 1
                run.steps[index].sessionCost = 0.18 * Double(index + 1)
            }
            if status.isFinished {
                run.steps[index].endedAt = started.addingTimeInterval(Double(index) * 240 + 200)
                run.steps[index].output =
                    "Plan: queue follow-ups in SessionModel+Turns.swift, show them above the draft, and cover the empty queue in PromptQueueTests."
            }
            if status == .awaitingApproval {
                run.steps[index].prompt = run.steps[index].step.prompt
                run.steps[index].waitingSince = now.addingTimeInterval(-90)
            }
        }
        return run
    }

    static let runningRun = run("Queue follow-ups while a turn runs", statuses: [.succeeded, .running])
    static let approvalRun = run(
        "Add a --json flag to the export command", statuses: [.succeeded, .awaitingApproval], minutesAgo: 40)
    static let failedRun = run(
        "Retry uploads when the network drops",
        statuses: [.succeeded, .failed("Codex stopped: the task's sandbox denied `swift test`.")], minutesAgo: 95)
    static let blockedRun = run(
        "Regenerate the schema types",
        statuses: [.succeeded, .blocked("Which schema version should the generated types follow, 0.9 or 1.0?")],
        minutesAgo: 30)
    static let limitedRun = run(
        "Steering support in the Codex adapter",
        statuses: [.succeeded, .limited("Claude Code · 5-hour limit reached · resets 3:05 PM")], minutesAgo: 70)
    static let finishedRun = run(
        "Task titles from the first prompt", statuses: [.succeeded, .succeeded, .succeeded],
        minutesAgo: 60 * 26)

    static let runs: [WorkflowRun] = [runningRun, approvalRun, failedRun, blockedRun, finishedRun].compactMap {
        $0
    }

    static let report = WorkflowTaskReport(
        reply: "Implemented the queue. `swift test` passes in Packages/ACP (212 tests).", cost: 0.42)

    // MARK: - Goals

    static func goal(
        _ status: GoalStatus, iterations: Int = 3, budget: GoalBudget = GoalBudget(maxIterations: 8),
        reason: String? = nil
    ) -> Goal {
        var goal = Goal(
            objective: "Make every test in PromptQueueTests pass without changing the public API",
            budget: budget, at: now.addingTimeInterval(-25 * 60), sessionCost: 0.10)
        goal.iterations = iterations
        goal.latestCost = 0.10 + 0.21 * Double(iterations)
        if status != .active {
            goal.transition(to: status, reason: reason, at: now.addingTimeInterval(-60))
        }
        return goal
    }

    static let activeGoal = goal(.active)
    static let pausedGoal = goal(.paused, reason: "You paused it.")
    static let blockedGoal = goal(
        .blocked, iterations: 5, reason: "Needs the simulator runtime for iPadOS 27 to run the UI tests.")
    static let limitedGoal = goal(.limited, iterations: 8, reason: "Used all 8 iterations.")
    static let completeGoal = goal(.complete, iterations: 4, reason: "All 14 tests pass.")

    // MARK: - Automations

    static let nightlyTriage = Automation(
        name: "Triage failing CI every morning", triggers: [.schedule(.daily(hour: 9, minute: 0))],
        action: .prompt("Look at the CI failures on main since yesterday and fix the ones caused by our code."),
        agent: "codex", project: project, createdAt: now.addingTimeInterval(-6 * 86_400))

    static let reviewBot = Automation(
        name: "Review my pull requests when they're opened", triggers: [.event(.pullRequestOpened)],
        action: .workflow(id: "plan-implement-review", input: "Review the pull request"), agent: "claude-code",
        project: project, repository: "binbandit/native", createdAt: now.addingTimeInterval(-20 * 86_400))

    static let paused = Automation(
        name: "Keep the dependency lockfiles fresh", triggers: [.schedule(.weekly(weekday: 2, hour: 8, minute: 30))],
        action: .goal(objective: "Update the Swift package pins and make sure everything builds", budget: .unlimited),
        project: project, isPaused: true, createdAt: now.addingTimeInterval(-40 * 86_400))

    static let automations = [nightlyTriage, reviewBot, paused]

    static func automationRuns(of automation: Automation) -> [AutomationRun] {
        var running = AutomationRun(
            automation: automation.id, reason: .scheduled(now.addingTimeInterval(-600)),
            startedAt: now.addingTimeInterval(-600), status: .running)
        running.workflowRun = runningRun?.id
        var needsYou = AutomationRun(
            automation: automation.id, reason: .manual, startedAt: now.addingTimeInterval(-3 * 3_600),
            status: .needsYou)
        needsYou.workflowRun = approvalRun?.id
        var succeeded = AutomationRun(
            automation: automation.id, reason: .missed(now.addingTimeInterval(-86_400)),
            startedAt: now.addingTimeInterval(-86_000), status: .succeeded)
        succeeded.endedAt = now.addingTimeInterval(-85_000)
        succeeded.summary = "Fixed 2 of 3 failures; the third is a flaky network test."
        var failed = AutomationRun(
            automation: automation.id, reason: .scheduled(now.addingTimeInterval(-2 * 86_400)),
            startedAt: now.addingTimeInterval(-2 * 86_400), status: .failed("Couldn't make a worktree: branch exists"))
        failed.endedAt = now.addingTimeInterval(-2 * 86_400 + 30)
        let skipped = AutomationRun(
            automation: automation.id, reason: .scheduled(now.addingTimeInterval(-3 * 86_400)),
            startedAt: now.addingTimeInterval(-3 * 86_400), status: .skipped("The previous run was still going"))
        return [running, needsYou, succeeded, failed, skipped]
    }
}
#endif
