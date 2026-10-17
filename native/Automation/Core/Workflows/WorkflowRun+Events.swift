import Foundation

extension WorkflowRun {
    /// Applies `event` and returns the work the host should do next. Events that don't fit the
    /// step's state (a late turn end, a double click) change nothing.
    mutating func handle(_ event: WorkflowEvent, at now: Date) -> [WorkflowEffect] {
        switch event {
        case .start:
            return advance(at: now)
        case .cancel:
            return cancel(at: now)
        case .reject:
            return cancel(at: now)
        case .pauseRun:
            setPaused(true)
            return []
        case .resumeRun:
            return resumeRun(at: now)
        case .taskCreated(let step, let task):
            guard let index = index(of: step), steps[index].status == .starting else { return [] }
            steps[index].task = task
            return send(firstPrompt(index, at: now), to: index, origin: .goal, at: now)
        case .taskFailed(let step, let message):
            guard let index = index(of: step), steps[index].status.isActive else { return [] }
            stop(index, as: .failed(message), at: now)
            return []
        case .turnEnded(let step, let outcome, let reply, let cost):
            return turnEnded(step, outcome: outcome, reply: reply, cost: cost, at: now)
        case .pullRequestOpened(let step, let result):
            guard let index = index(of: step), steps[index].status == .starting else { return [] }
            finish(index, output: result.url.absoluteString, at: now)
            return advance(at: now)
        case .scriptFinished(let step, let output):
            guard let index = index(of: step), steps[index].status == .starting else { return [] }
            finish(index, output: output, at: now)
            return advance(at: now)
        case .pullRequestFailed(let step, let message), .scriptFailed(let step, let message):
            guard let index = index(of: step), steps[index].status == .starting else { return [] }
            stop(index, as: .failed(message), at: now)
            return []
        case .skip, .stop:
            return isCancelled ? [] : handleUserAction(event, at: now)
        default:
            guard !isCancelled else { return [] }
            // Acting on a step means going on, so a paused run picks back up first.
            let resumed = isPaused ? resumeRun(at: now) : []
            return resumed + handleUserAction(event, at: now)
        }
    }

    private mutating func handleUserAction(_ event: WorkflowEvent, at now: Date) -> [WorkflowEffect] {
        switch event {
        case .approve(let step, let prompt):
            guard let index = index(of: step), steps[index].status == .awaitingApproval else { return [] }
            if let prompt = prompt?.trimmingCharacters(in: .whitespacesAndNewlines), !prompt.isEmpty {
                steps[index].prompt = prompt
            }
            return begin(index, at: now)
        case .skip(let step):
            guard let index = index(of: step), !steps[index].status.isActive, !steps[index].status.isFinished else { return [] }
            steps[index].status = .skipped
            steps[index].endedAt = now
            steps[index].waitingSince = nil
            return advance(at: now)
        case .retry(let step):
            guard let index = index(of: step), steps[index].status.isStopped else { return [] }
            if steps[index].step.continues == nil {
                steps[index].task = nil
            }
            steps[index].goal = nil
            steps[index].turns = 0
            return begin(index, at: now)
        case .resume(let step):
            guard let index = index(of: step), steps[index].status.isStopped else { return [] }
            guard steps[index].task != nil else { return begin(index, at: now) }
            if steps[index].goal != nil {
                resumeGoal(index, at: now)
                let text = steps[index].goal?.nextPrompt(at: now) ?? Self.continuePrompt
                return send(text, to: index, origin: .goal, at: now)
            }
            let text = steps[index].status == .interrupted ? Self.interruptedPrompt : Self.continuePrompt
            return send(text, to: index, origin: .user, at: now)
        case .reply(let step, let text):
            let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let index = index(of: step), steps[index].status.isStopped, !text.isEmpty, steps[index].task != nil else { return [] }
            // The answer is what the step stopped for, so its goal picks back up with it.
            resumeGoal(index, at: now)
            return send(text, to: index, origin: .user, at: now)
        case .accept(let step):
            guard let index = index(of: step), steps[index].status.isStopped else { return [] }
            finish(index, output: GoalMarker.stripping(steps[index].latestReply ?? ""), at: now)
            return advance(at: now)
        case .stop(let step):
            guard let index = index(of: step), steps[index].status.isActive else { return [] }
            if let task = steps[index].task, steps[index].status == .running {
                // The turn's end, cancelled, settles the step.
                return [.cancelTask(task)]
            }
            stop(index, as: .cancelled, at: now)
            return []
        default:
            return []
        }
    }

    static let continuePrompt = "Continue where you left off."
    /// Sent when the user resumes a step that was cut off, so the agent checks what its last turn
    /// actually finished before carrying on.
    static let interruptedPrompt = "Native quit while you were working on this, so your last turn was cut off. Check what it finished, then continue where you left off."

    private mutating func turnEnded(_ step: String, outcome: TurnOutcome, reply: String?, cost: Double?, at now: Date) -> [WorkflowEffect] {
        guard let index = index(of: step), steps[index].status == .running else { return [] }
        steps[index].turns += 1
        steps[index].latestReply = reply ?? steps[index].latestReply
        steps[index].sessionCost = cost ?? steps[index].sessionCost
        if isCancelled {
            stop(index, as: .cancelled, at: now)
            return []
        }
        if var loop = steps[index].goal {
            let next = loop.turnDidEnd(outcome, reply: reply, sessionCost: cost, at: now)
            steps[index].goal = loop
            if let next {
                return send(next, to: index, origin: .goal, at: now)
            }
            settleGoalStep(index, loop: loop, outcome: outcome, reply: reply, at: now)
        } else {
            switch outcome {
            case .ended: finish(index, output: GoalMarker.stripping(reply ?? ""), at: now)
            case .cancelled: stop(index, as: .cancelled, at: now)
            case .limited(let message): stop(index, as: .limited(message), at: now)
            case .refused: stop(index, as: .failed("The agent declined to continue."), at: now)
            case .failed(let message): stop(index, as: .failed(message), at: now)
            }
        }
        return advance(at: now)
    }

    private mutating func settleGoalStep(_ index: Int, loop: GoalLoop, outcome: TurnOutcome, reply: String?, at now: Date) {
        let reason = loop.goal.lastReason ?? loop.goal.status.label
        switch loop.goal.status {
        case .complete:
            finish(index, output: GoalMarker.stripping(reply ?? ""), at: now)
        case .blocked:
            stop(index, as: .blocked(reason), at: now)
        case .limited:
            stop(index, as: .limited(reason), at: now)
        case .paused:
            stop(index, as: outcome == .cancelled ? .cancelled : .failed(reason), at: now)
        case .active:
            // A loop that's active but has nothing to send would stall the run; stop it visibly.
            stop(index, as: .failed("The goal stopped without a next step."), at: now)
        }
    }

    /// Makes a step's goal active again, granting a spent budget once more.
    private mutating func resumeGoal(_ index: Int, at now: Date) {
        guard var loop = steps[index].goal else { return }
        if !loop.resume(at: now) {
            loop.extendBudget(at: now)
            loop.resume(at: now)
        }
        steps[index].goal = loop
    }

    private mutating func stop(_ index: Int, as status: WorkflowStepStatus, at now: Date) {
        steps[index].status = status
        steps[index].endedAt = now
        if case .blocked = status {
            steps[index].waitingSince = now
        }
    }

    private mutating func resumeRun(at now: Date) -> [WorkflowEffect] {
        guard isPaused else { return [] }
        setPaused(false)
        var effects: [WorkflowEffect] = []
        for index in steps.indices where steps[index].status == .paused {
            let text = steps[index].goal?.nextPrompt(at: now) ?? steps[index].prompt ?? Self.continuePrompt
            effects += send(text, to: index, origin: .goal, at: now)
        }
        return effects + advance(at: now)
    }

    private mutating func cancel(at now: Date) -> [WorkflowEffect] {
        guard !isCancelled else { return [] }
        markCancelled(at: now)
        var effects: [WorkflowEffect] = []
        for index in steps.indices {
            switch steps[index].status {
            case .running:
                if let task = steps[index].task {
                    effects.append(.cancelTask(task))
                }
            case .waiting, .awaitingApproval, .starting, .paused, .blocked:
                stop(index, as: .cancelled, at: now)
            default:
                break
            }
        }
        return effects
    }
}
