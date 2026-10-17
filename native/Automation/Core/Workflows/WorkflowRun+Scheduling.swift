import Foundation

extension WorkflowRun {
    /// Starts every step whose dependencies have finished, or stops it at its gate.
    mutating func advance(at now: Date) -> [WorkflowEffect] {
        guard !isCancelled, !isPaused else { return [] }
        var effects: [WorkflowEffect] = []
        // Dependencies come earlier in the definition, so one pass in order sees them settled.
        for index in steps.indices where steps[index].status == .waiting {
            let dependencies = definition.dependencies(of: steps[index].step)
            guard dependencies.allSatisfy({ stepRun($0)?.status.isFinished == true }) else { continue }
            steps[index].prompt = renderedPrompt(for: steps[index].step)
            if steps[index].step.approval != nil {
                steps[index].status = .awaitingApproval
                steps[index].waitingSince = now
            } else {
                effects += begin(index, at: now)
            }
        }
        noteEnded(at: now)
        return effects
    }

    /// Runs a step that's cleared to go: opens its pull request, prompts the task it continues, or
    /// asks for a task of its own.
    mutating func begin(_ index: Int, at now: Date) -> [WorkflowEffect] {
        let step = steps[index].step
        steps[index].startedAt = steps[index].startedAt ?? now
        steps[index].endedAt = nil
        steps[index].waitingSince = nil
        let prompt = steps[index].prompt ?? renderedPrompt(for: step)
        steps[index].prompt = prompt
        switch step.kind {
        case .pullRequest:
            steps[index].status = .starting
            let title = WorkflowTemplate.render(step.pullRequest?.title ?? "{{title}}", with: templateValues)
            let draft = WorkflowPullRequestDraft(title: title, body: prompt, cwd: cwd, isDraft: step.pullRequest?.isDraft ?? false)
            return [.openPullRequest(step: step.id, draft)]
        case .script:
            steps[index].status = .starting
            return [.runScript(step: step.id, source: step.script ?? "", input: prompt, cwd: cwd)]
        case .agent:
            let continuedTask = step.continues.flatMap { stepRun($0)?.task }
            if let continuedTask, let continued = step.continues {
                steps[index].task = continuedTask
                steps[index].costBaseline = stepRun(continued)?.sessionCost
                steps[index].sessionCost = steps[index].costBaseline
            }
            if let budget = step.goal {
                steps[index].goal = GoalLoop(objective: prompt, budget: budget, at: now, sessionCost: steps[index].costBaseline)
            }
            if continuedTask != nil {
                return send(firstPrompt(index, at: now), to: index, origin: .goal, at: now)
            }
            guard let agent = steps[index].assignment.agent else {
                steps[index].status = .failed("No agent is available to run this step.")
                return []
            }
            steps[index].status = .starting
            return [.createTask(step: step.id, agent: agent, title: "\(step.title): \(title)")]
        }
    }

    /// The first prompt a step's task gets: the goal's kickoff, or the step's prompt.
    func firstPrompt(_ index: Int, at now: Date) -> String {
        steps[index].goal?.nextPrompt(at: now) ?? steps[index].prompt ?? ""
    }

    /// Sends `text` into the step's task, telling its goal loop who sent it. While the run is
    /// paused, Native's own prompts wait instead; the user's always go out.
    mutating func send(_ text: String, to index: Int, origin: GoalLoop.Origin, at now: Date) -> [WorkflowEffect] {
        guard let task = steps[index].task else { return [] }
        if isPaused, origin == .goal {
            steps[index].status = .paused
            return []
        }
        steps[index].goal?.turnWillStart(origin, at: now)
        steps[index].status = .running
        steps[index].waitingSince = nil
        steps[index].endedAt = nil
        return [.prompt(step: steps[index].id, task: task, text: text)]
    }

    mutating func finish(_ index: Int, output: String, at now: Date) {
        steps[index].status = .succeeded
        steps[index].output = output
        steps[index].endedAt = now
        steps[index].waitingSince = nil
    }

    func renderedPrompt(for step: WorkflowStep) -> String {
        let template = step.kind == .pullRequest ? step.pullRequest?.body ?? "" : step.prompt
        return WorkflowTemplate.render(template, with: templateValues)
    }
}
