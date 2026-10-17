import Foundation
import NativeAutomation

extension Teamwork {
    /// Applies `event` and returns the work the host should do next. Events that don't fit the
    /// state they arrive in (a late turn end, a double click) change nothing.
    public mutating func handle(_ event: TeamworkEvent, at now: Date) -> [TeamworkEffect] {
        let effects = isStopped && !event.reachesStopped ? [] : apply(event, at: now)
        updatedAt = now
        updateClock(at: now)
        return effects
    }

    private mutating func apply(_ event: TeamworkEvent, at now: Date) -> [TeamworkEffect] {
        switch event {
        case .start:
            guard base == nil, lead.status == .waiting else { return [] }
            note(.progress, usesWorktree ? "Making a worktree for the crew." : "The crew works in the project folder.", at: now)
            return [.prepareBase(project: project, title: title, worktree: usesWorktree)]
        case .baseReady(let url):
            guard base == nil else { return [] }
            base = url
            baseError = nil
            note(.progress, "\(crew.lead.name) is planning the route.", slot: .lead, at: now)
            return startLead(.planning, at: now)
        case .baseFailed(let message):
            baseError = message
            note(.attention, "Couldn't make the crew's workspace: \(message)", at: now)
            return []
        case .taskCreated(let slot, let task):
            return taskCreated(slot, task: task, at: now)
        case .taskFailed(let slot, let message):
            stop(slot, as: .failed(message), at: now)
            note(.attention, "\(name(of: slot)) couldn't start: \(message)", slot: slot, at: now)
            return []
        case .turnEnded(let slot, let outcome, let reply, let cost):
            switch slot {
            case .lead: return leadTurnEnded(outcome, reply: reply, cost: cost, at: now)
            case .assignment(let id): return assignmentTurnEnded(id, outcome: outcome, reply: reply, cost: cost, at: now)
            case .checkpoint(let leg): return checkpointTurnEnded(leg, outcome: outcome, reply: reply, cost: cost, at: now)
            }
        case .pullRequestOpened(let result):
            guard isOpeningPullRequest else { return [] }
            isOpeningPullRequest = false
            pullRequest = result
            pullRequestError = nil
            note(.success, "Opened the pull request\(result.number.map { " #\($0)" } ?? "").", at: now)
            finish(at: now)
            return []
        case .pullRequestFailed(let message):
            guard isOpeningPullRequest else { return [] }
            isOpeningPullRequest = false
            pullRequestError = message
            note(.attention, "Couldn't open the pull request: \(message)", at: now)
            return []
        case .documentRestored(let path):
            note(.attention, "Put back \(path): it was changed outside Native.", at: now)
            return []
        default:
            return userAction(event, at: now)
        }
    }

    private mutating func userAction(_ event: TeamworkEvent, at now: Date) -> [TeamworkEffect] {
        switch event {
        case .approve(let edited):
            guard approvedAt == nil, lead.status == .succeeded, route != nil, base != nil else { return [] }
            approvedAt = now
            lead.waitingSince = nil
            lead.job = .conversation
            sync(to: edited)
            note(.user, "You approved the route: \(edited.legs.count) \(edited.legs.count == 1 ? "leg" : "legs"), \(edited.assignments.count) \(edited.assignments.count == 1 ? "assignment" : "assignments").", at: now)
            return advance(at: now)
        case .requestChanges(let text):
            let text = text.trimmed
            guard approvedAt == nil, !text.isEmpty, lead.task != nil, !lead.status.isActive else { return [] }
            feedback = text
            note(.user, "You asked the lead for changes.", slot: .lead, at: now)
            return startLead(.revising, at: now)
        case .discard:
            guard approvedAt == nil else { return [] }
            note(.user, "You discarded the route.", at: now)
            return stopAll(at: now)
        case .pause:
            guard approvedAt != nil, !isPaused else { return [] }
            isPaused = true
            note(.user, "You paused the expedition.", at: now)
            return []
        case .resume:
            guard isPaused else { return [] }
            isPaused = false
            note(.user, "You resumed the expedition.", at: now)
            return releaseHeld(at: now) + advance(at: now)
        case .stop:
            note(.user, "You stopped the expedition.", at: now)
            return stopAll(at: now)
        case .extendBudget:
            budget = budget.extended(cost: cost, active: activeTime(at: now))
            note(.user, "You added to the budget.", at: now)
            return releaseHeld(at: now) + advance(at: now)
        case .wrapUp:
            guard approvedAt != nil, !legsSettled else { return [] }
            isWrappingUp = true
            isPaused = false
            for index in assignments.indices where !assignments[index].status.isActive && !assignments[index].status.isFinished {
                assignments[index].status = .skipped
                assignments[index].waitingSince = nil
            }
            for index in checkpoints.indices where !checkpoints[index].status.isActive && !checkpoints[index].status.isFinished {
                checkpoints[index].status = .skipped
                checkpoints[index].waitingSince = nil
            }
            note(.user, "You asked to wrap up: what hasn't started is skipped.", at: now)
            return advance(at: now)
        case .messageLead(let text):
            let text = text.trimmed
            guard !text.isEmpty, let task = lead.task else { return [] }
            note(.user, "You messaged the lead.", slot: .lead, at: now)
            if lead.status.isActive {
                return [.prompt(.lead, task: task, text: text)]
            }
            if approvedAt != nil, !legsSettled {
                lead.job = .conversation
            }
            return send(text, to: .lead, at: now)
        case .retryPullRequest:
            guard pullRequestError != nil, let draft = pullRequestDraft else { return [] }
            pullRequestError = nil
            isOpeningPullRequest = true
            return [.openPullRequest(draft)]
        case .approveRouteChange:
            guard let change = pendingRouteChange else { return [] }
            pendingRouteChange = nil
            lead.waitingSince = nil
            sync(to: change)
            note(.user, "You accepted the lead's changes to the legs ahead.", slot: .lead, at: now)
            return advance(at: now)
        case .keepRoute:
            guard pendingRouteChange != nil else { return [] }
            pendingRouteChange = nil
            lead.waitingSince = nil
            note(.user, "You kept the route as approved.", slot: .lead, at: now)
            return advance(at: now)
        case .limitResets(let slot, let date):
            if case .assignment(let id) = slot, let index = assignmentIndex(id) {
                assignments[index].resumeAt = date
            }
            return []
        default:
            return slotAction(event, at: now)
        }
    }

    /// Stops every turn and holds everything else. Sessions, reports and the base stay.
    mutating func stopAll(at now: Date) -> [TeamworkEffect] {
        guard !isStopped else { return [] }
        isStopped = true
        isPaused = false
        isOpeningPullRequest = false
        var effects: [TeamworkEffect] = []
        for slot in allSlots {
            guard let status = status(of: slot), !status.isFinished, status != .cancelled else { continue }
            if status == .running, let task = task(of: slot) {
                effects.append(.cancelTask(task))
            }
            if status != .succeeded {
                set(slot, status: .cancelled, at: now)
            }
        }
        return effects
    }

    var allSlots: [CrewSlot] {
        [.lead] + assignments.map { .assignment($0.id) } + checkpoints.map { .checkpoint($0.leg) }
    }

    /// The draft for the pull request at the end: the objective's title, the debrief as its body.
    public var pullRequestDraft: WorkflowPullRequestDraft? {
        guard let base, let debrief else { return nil }
        let agents = Set((assignments.map(\.assignment.assignee) + [crew.lead.id, crew.reviewer.id]).compactMap { crew.agent($0)?.name })
        let footer = "Carried out in Native by \(agents.sorted().joined(separator: ", ")): \(finishedCount) \(finishedCount == 1 ? "assignment" : "assignments") across \(route?.legs.count ?? 0) checked \(route?.legs.count == 1 ? "leg" : "legs")."
        return WorkflowPullRequestDraft(title: title, body: debrief + "\n\n---\n" + footer, cwd: base, isDraft: settings.draftPullRequest)
    }

    mutating func finish(at now: Date) {
        guard endedAt == nil else { return }
        endedAt = now
        note(.success, "The expedition is complete.", at: now)
    }

    mutating func note(_ kind: LogbookEntry.Kind, _ text: String, slot: CrewSlot? = nil, at now: Date) {
        log.append(LogbookEntry(at: now, kind: kind, text: text, slot: slot))
    }

    /// Runs the active clock while anyone works, and banks it when nobody does.
    mutating func updateClock(at now: Date) {
        if isAnyoneWorking, activeSince == nil {
            activeSince = now
        } else if !isAnyoneWorking, let since = activeSince {
            bankedActive += max(0, now.timeIntervalSince(since))
            activeSince = nil
        }
    }

    /// The expedition as found on the next launch. Turns in flight died with Native, so their seats
    /// are interrupted until the user resumes them, goals stop their clocks, and the active clock
    /// stops at the last thing that happened.
    public func restored() -> Teamwork {
        var expedition = self
        if let since = expedition.activeSince {
            expedition.bankedActive += max(0, updatedAt.timeIntervalSince(since))
            expedition.activeSince = nil
        }
        expedition.isOpeningPullRequest = false
        if lead.status.isActive {
            expedition.lead.status = .interrupted
            expedition.lead.waitingSince = updatedAt
        }
        for index in expedition.assignments.indices where expedition.assignments[index].status.isActive {
            expedition.assignments[index].status = .interrupted
            expedition.assignments[index].goal = expedition.assignments[index].goal?.restored()
            expedition.assignments[index].waitingSince = updatedAt
        }
        for index in expedition.checkpoints.indices where expedition.checkpoints[index].status.isActive {
            expedition.checkpoints[index].status = .interrupted
            expedition.checkpoints[index].waitingSince = updatedAt
        }
        if pullRequestError == nil, isOpeningPullRequest {
            expedition.pullRequestError = "Native quit while the pull request was opening. Check GitHub before retrying."
        }
        return expedition
    }
}

extension TeamworkEvent {
    /// Results that still count after a stop: what was already under way finishing.
    var reachesStopped: Bool {
        switch self {
        case .turnEnded, .documentRestored: true
        default: false
        }
    }
}
