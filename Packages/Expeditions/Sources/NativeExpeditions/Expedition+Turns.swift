import Foundation
import NativeAutomation

extension Expedition {
    mutating func taskCreated(_ slot: CrewSlot, task: UUID, at now: Date) -> [ExpeditionEffect] {
        guard status(of: slot) == .starting else { return [] }
        switch slot {
        case .lead:
            lead.task = task
            return send(leadPrompt(), to: .lead, at: now)
        case .assignment(let id):
            guard let index = assignmentIndex(id) else { return [] }
            assignments[index].task = task
            return sendGoalPrompt(index, at: now)
        case .checkpoint(let leg):
            guard let index = checkpointIndex(leg), let legInfo = self.leg(leg) else { return [] }
            checkpoints[index].task = task
            return send(ExpeditionPrompt.checkpoint(self, leg: legInfo), to: slot, at: now)
        }
    }

    // MARK: - Lead

    mutating func leadTurnEnded(
        _ outcome: TurnOutcome, reply: String?, cost: Double?, at now: Date
    ) -> [ExpeditionEffect] {
        guard lead.status == .running else { return [] }
        lead.latestReply = reply ?? lead.latestReply
        lead.sessionCost = cost ?? lead.sessionCost
        guard outcome == .ended else {
            if case .reviewingLeg = lead.job {
                // A lead that can't look ahead mustn't hold the crew: the approved route stands.
                lead.status = .succeeded
                lead.job = .conversation
                note(
                    .attention, "The lead couldn't review the legs ahead (\(outcome.summary)), so the route stands.",
                    slot: .lead, at: now)
                return advance(at: now)
            }
            stop(.lead, as: outcome.stoppedStatus, at: now)
            note(.attention, "The lead stopped: \(outcome.summary).", slot: .lead, at: now)
            return []
        }
        let reply = reply ?? ""
        switch lead.job {
        case .planning, .revising:
            return readRoute(reply, at: now)
        case .conversation where approvedAt == nil && RouteParser.containsRoute(reply):
            return readRoute(reply, at: now)
        case .conversation:
            lead.status = .succeeded
            return approvedAt == nil ? [] : advance(at: now)
        case .reviewingLeg:
            lead.status = .succeeded
            lead.job = .conversation
            if RouteParser.containsRoute(reply) {
                reviseLegsAhead(reply, at: now)
            } else {
                note(.progress, "The lead kept the legs ahead as they are.", slot: .lead, at: now)
            }
            return advance(at: now)
        case .debriefing:
            lead.status = .succeeded
            debrief = GoalMarker.stripping(reply).nilIfEmpty ?? "The crew finished every assignment."
            note(.success, "The lead wrote the debrief.", slot: .lead, at: now)
            guard settings.opensPullRequest, let draft = pullRequestDraft else {
                finish(at: now)
                return []
            }
            isOpeningPullRequest = true
            return [.openPullRequest(draft)]
        }
    }

    private mutating func readRoute(_ reply: String, at now: Date) -> [ExpeditionEffect] {
        switch RouteParser.parse(reply, builders: crew.builders.map(\.id)) {
        case .success(var parsed):
            // Answers carry over to the same questions in a revision.
            for index in parsed.questions.indices {
                parsed.questions[index].answer =
                    route?.questions.first { $0.text == parsed.questions[index].text }?.answer
            }
            let changed = route.map { parsed.changedAssignments(since: $0).count }
            if let route {
                previousRoutes.append(route)
            }
            route = parsed
            lead.status = .succeeded
            lead.job = .conversation
            lead.unreadRoutes = 0
            lead.waitingSince = now
            let size =
                "\(parsed.legs.count) \(parsed.legs.count == 1 ? "leg" : "legs"), \(parsed.assignments.count) \(parsed.assignments.count == 1 ? "assignment" : "assignments")"
            note(
                .attention,
                changed.map {
                    $0 == 0
                        ? "The lead sent the route again, unchanged."
                        : "The lead revised the route (\($0) \($0 == 1 ? "assignment" : "assignments") changed): \(size)."
                } ?? "The lead proposed a route: \(size).", slot: .lead, at: now)
            return []
        case .failure(let problem):
            lead.unreadRoutes += 1
            guard lead.unreadRoutes <= 2 else {
                stop(.lead, as: .blocked("Native couldn't read the lead's route: \(problem.message)"), at: now)
                return []
            }
            note(.progress, "Native couldn't read the route and asked the lead again.", slot: .lead, at: now)
            return send(ExpeditionPrompt.routeProblem(problem.message), to: .lead, at: now)
        }
    }

    /// Applies the lead's revision of the legs ahead: on its own when it only adds work, otherwise
    /// as a change for the user to accept, because it rewrites what they approved.
    private mutating func reviseLegsAhead(_ reply: String, at now: Date) {
        guard let route, let current = currentLeg, let start = route.legs.firstIndex(where: { $0.id == current.id })
        else { return }
        let done = route.assignments.filter { assignment($0.id)?.status != .waiting }.map(\.id)
        let earlier = Set(route.legs[..<start].flatMap(\.assignments).map(\.id))
        switch RouteParser.parse(reply, builders: crew.builders.map(\.id), earlier: earlier) {
        case .failure(let problem):
            note(
                .attention,
                "The lead's revision of the legs ahead couldn't be read (\(problem.message)), so the route stands.",
                slot: .lead, at: now)
        case .success(let revision):
            var revised = route
            let ahead = Array(route.legs[start...])
            revised.legs =
                Array(route.legs[..<start])
                + revision.legs.enumerated().map { offset, leg in
                    Route.Leg(
                        id: offset < ahead.count
                            ? ahead[offset].id : "leg-\(route.legs.count + offset - ahead.count + 1)", title: leg.title,
                        outcome: leg.outcome, assignments: leg.assignments)
                }
            // Work that has started stays exactly as it is, wherever the lead put it.
            let missingStarted = done.filter { id in
                revised.assignments.first { $0.id == id } != route.assignments.first { $0.id == id }
            }
            let rewritesApproved = route.assignments.contains { old in
                revised.assignments.first { $0.id == old.id } != old
            }
            // Growth past the size of the approved route is a change of scope, so the user decides.
            let added = revised.assignments.count - route.assignments.count
            if missingStarted.isEmpty, !rewritesApproved, added <= route.assignments.count {
                sync(to: revised)
                note(
                    .progress,
                    "The lead added \(added) \(added == 1 ? "assignment" : "assignments") to the legs ahead.",
                    slot: .lead, at: now)
            } else if missingStarted.isEmpty {
                pendingRouteChange = revised
                lead.waitingSince = now
                note(
                    .attention, "The lead wants to change the legs ahead. Review the change to go on.", slot: .lead,
                    at: now)
            } else {
                note(
                    .attention, "The lead's revision changed work that had already started, so the route stands.",
                    slot: .lead, at: now)
            }
        }
    }

    // MARK: - Builders

    mutating func assignmentTurnEnded(
        _ id: String, outcome: TurnOutcome, reply: String?, cost: Double?, at now: Date
    ) -> [ExpeditionEffect] {
        guard let index = assignmentIndex(id), assignments[index].status == .running else { return [] }
        assignments[index].turns += 1
        assignments[index].latestReply = reply ?? assignments[index].latestReply
        assignments[index].sessionCost = cost ?? assignments[index].sessionCost
        let slot = CrewSlot.assignment(id)
        if case .failed(let message) = outcome, assignments[index].automaticRecoveries == 0 {
            // An unattended crew shouldn't stall on one crash; a second one waits for the user.
            assignments[index].automaticRecoveries += 1
            assignments[index].goal?.pause(at: now, reason: message)
            assignments[index].goal?.resume(at: now)
            note(
                .attention,
                "\(agent(of: slot).name)'s turn on \(name(of: slot)) failed (\(message)). Native asked it to pick up where it left off.",
                slot: slot, at: now)
            return send(ExpeditionPrompt.failed(message), to: slot, at: now)
        }
        guard var loop = assignments[index].goal else {
            settle(index, outcome: outcome, reply: reply, at: now)
            return advance(at: now)
        }
        let next = loop.turnDidEnd(outcome, reply: reply, sessionCost: cost, at: now)
        assignments[index].goal = loop
        if let next {
            if isHeld(at: now) {
                // Held by a pause or the budget: the next prompt goes out when that lifts.
                assignments[index].status = .paused
                return []
            }
            return send(next, to: slot, at: now, origin: .goal)
        }
        settleGoal(index, loop: loop, outcome: outcome, reply: reply, at: now)
        return advance(at: now)
    }

    private mutating func settleGoal(_ index: Int, loop: GoalLoop, outcome: TurnOutcome, reply: String?, at now: Date) {
        let reason = loop.goal.lastReason ?? loop.goal.status.label
        let slot = CrewSlot.assignment(assignments[index].id)
        switch loop.goal.status {
        case .complete:
            complete(index, report: GoalMarker.stripping(reply ?? ""), at: now)
        case .blocked:
            stop(slot, as: .blocked(reason), at: now)
            note(.attention, "\(agent(of: slot).name) needs you on \(name(of: slot)).", slot: slot, at: now)
        case .limited:
            stop(slot, as: .limited(reason), at: now)
            note(.attention, "\(name(of: slot)) stopped: \(reason).", slot: slot, at: now)
        case .paused:
            stop(slot, as: outcome == .cancelled ? .cancelled : .failed(reason), at: now)
            note(.attention, "\(name(of: slot)) stopped: \(reason).", slot: slot, at: now)
        case .active:
            stop(slot, as: .failed("The goal stopped without a next step."), at: now)
        }
    }

    /// For an assignment without a goal, which only a restored, older record can be.
    private mutating func settle(_ index: Int, outcome: TurnOutcome, reply: String?, at now: Date) {
        if outcome == .ended {
            complete(index, report: GoalMarker.stripping(reply ?? ""), at: now)
        } else {
            stop(.assignment(assignments[index].id), as: outcome.stoppedStatus, at: now)
        }
    }

    mutating func complete(_ index: Int, report: String, at now: Date) {
        assignments[index].status = .succeeded
        assignments[index].report = report.nilIfEmpty ?? assignments[index].latestReply
        assignments[index].endedAt = now
        assignments[index].waitingSince = nil
        let slot = CrewSlot.assignment(assignments[index].id)
        note(.success, "\(agent(of: slot).name) finished \(name(of: slot)).", slot: slot, at: now)
    }

    // MARK: - Reviewer

    mutating func checkpointTurnEnded(
        _ leg: String, outcome: TurnOutcome, reply: String?, cost: Double?, at now: Date
    ) -> [ExpeditionEffect] {
        guard let index = checkpointIndex(leg), checkpoints[index].status == .running, let legInfo = self.leg(leg)
        else { return [] }
        checkpoints[index].latestReply = reply ?? checkpoints[index].latestReply
        checkpoints[index].sessionCost = cost ?? checkpoints[index].sessionCost
        let slot = CrewSlot.checkpoint(leg)
        guard outcome == .ended else {
            stop(slot, as: outcome.stoppedStatus, at: now)
            note(.attention, "\(name(of: slot)) stopped: \(outcome.summary).", slot: slot, at: now)
            return []
        }
        guard let verdict = CheckpointVerdict(parsing: reply ?? "") else {
            checkpoints[index].unreadReplies += 1
            if checkpoints[index].unreadReplies == 1 {
                return send(ExpeditionPrompt.verdictReminder, to: slot, at: now)
            }
            stop(
                slot,
                as: .blocked(
                    "The reviewer didn't end with a verdict. Read its reply, then pass the leg or ask for another round."
                ), at: now)
            return []
        }
        checkpoints[index].unreadReplies = 0
        checkpoints[index].verdicts.append(verdict)
        switch verdict.outcome {
        case .pass:
            checkpoints[index].status = .succeeded
            checkpoints[index].endedAt = now
            note(
                .success, "\(legInfo.title) passed its checkpoint\(verdict.note.map { ": \($0)" } ?? ".")", slot: slot,
                at: now)
            return afterCheckpointPassed(legInfo, at: now)
        case .changes:
            let rounds = checkpoints[index].rounds
            let allowed = settings.fixRounds + checkpoints[index].extraRounds
            guard rounds <= allowed else {
                stop(
                    slot,
                    as: .blocked(
                        "Still asking for changes after \(rounds - 1) \(rounds - 1 == 1 ? "round" : "rounds") of fixes\(verdict.note.map { ": \($0)" } ?? ".")"
                    ), at: now)
                note(
                    .attention, "\(legInfo.title)'s checkpoint is still asking for changes. It needs you to decide.",
                    slot: slot, at: now)
                return []
            }
            note(
                .attention, "\(legInfo.title)'s checkpoint asked for changes\(verdict.note.map { ": \($0)" } ?? ".")",
                slot: slot, at: now)
            return startFixRound(index, verdict: verdict, at: now)
        }
    }

    // MARK: - The user, on one seat

    mutating func slotAction(_ event: ExpeditionEvent, at now: Date) -> [ExpeditionEffect] {
        switch event {
        case .message(let slot, let text):
            let text = text.trimmed
            guard !text.isEmpty, let status = status(of: slot), let task = task(of: slot) else { return [] }
            if status.isActive {
                return [.message(slot, task: task, text: text)]
            }
            guard status.isStopped || (status == .succeeded && slot == .lead) else { return [] }
            resumeGoal(slot, at: now)
            note(.user, "You replied to \(name(of: slot)).", slot: slot, at: now)
            return send(text, to: slot, at: now, origin: .user)
        case .retry(let slot):
            return retry(slot, at: now)
        case .resumeSlot(let slot):
            return resume(slot, at: now)
        case .limitReset(let slot):
            guard case .limited = status(of: slot) else { return [] }
            return resume(slot, at: now)
        case .skip(let slot):
            guard slot != .lead, let status = status(of: slot), !status.isActive, !status.isFinished else { return [] }
            set(slot, status: .skipped, at: now)
            note(.user, "You skipped \(name(of: slot)).", slot: slot, at: now)
            return advance(at: now)
        case .accept(let slot):
            guard let status = status(of: slot), status.isStopped else { return [] }
            switch slot {
            case .lead:
                return []
            case .assignment(let id):
                guard let index = assignmentIndex(id) else { return [] }
                complete(index, report: GoalMarker.stripping(assignments[index].latestReply ?? ""), at: now)
                note(.user, "You accepted \(name(of: slot)) as done.", slot: slot, at: now)
                return advance(at: now)
            case .checkpoint(let leg):
                guard let index = checkpointIndex(leg), let legInfo = self.leg(leg) else { return [] }
                checkpoints[index].status = .succeeded
                checkpoints[index].endedAt = now
                checkpoints[index].waitingSince = nil
                note(.user, "You passed \(legInfo.title)'s checkpoint.", slot: slot, at: now)
                return afterCheckpointPassed(legInfo, at: now)
            }
        case .stopSlot(let slot):
            guard status(of: slot) == .running, let task = task(of: slot) else { return [] }
            return [.cancelTask(task)]
        case .reassign(let id, let agent):
            guard let index = assignmentIndex(id), !assignments[index].status.isActive,
                !assignments[index].status.isFinished
            else { return [] }
            if !crew.builders.contains(agent) {
                crew.builders.append(agent)
            }
            assignments[index].assignment.assignee = agent.id
            assignments[index].task = nil
            assignments[index].goal = nil
            assignments[index].status = .waiting
            assignments[index].waitingSince = nil
            note(.user, "You moved \(name(of: .assignment(id))) to \(agent.name).", slot: .assignment(id), at: now)
            return advance(at: now)
        case .anotherRound(let leg):
            guard let index = checkpointIndex(leg), checkpoints[index].status.isStopped,
                let verdict = checkpoints[index].latestVerdict
            else { return [] }
            checkpoints[index].extraRounds += 1
            note(.user, "You asked for another round of fixes.", slot: .checkpoint(leg), at: now)
            return startFixRound(index, verdict: verdict, at: now)
        case .finishWithoutPullRequest:
            guard pullRequestError != nil else { return [] }
            pullRequestError = nil
            note(.user, "You finished without a pull request.", at: now)
            finish(at: now)
            return []
        default:
            return []
        }
    }

    /// Picks a stopped seat back up in its session, telling the agent if its turn was cut off.
    private mutating func resume(_ slot: CrewSlot, at now: Date) -> [ExpeditionEffect] {
        guard let status = status(of: slot), status.isStopped else { return [] }
        guard task(of: slot) != nil else { return retry(slot, at: now) }
        resumeGoal(slot, at: now)
        let prefix = status == .interrupted ? ExpeditionPrompt.interrupted : nil
        switch slot {
        case .assignment(let id):
            guard let index = assignmentIndex(id) else { return [] }
            return sendGoalPrompt(index, at: now, prefix: prefix)
        case .lead:
            let reminder =
                [.planning, .revising].contains(lead.job)
                ? "\n\nEnd your reply with the route between \(RouteParser.openTag) and \(RouteParser.closeTag), as asked."
                : ""
            return send((prefix ?? LimitText.continuation) + reminder, to: .lead, at: now)
        case .checkpoint:
            return send(
                (prefix ?? LimitText.continuation) + "\n\n" + ExpeditionPrompt.verdictReminder, to: slot, at: now)
        }
    }

    private mutating func retry(_ slot: CrewSlot, at now: Date) -> [ExpeditionEffect] {
        guard let status = status(of: slot), status.isStopped else { return [] }
        switch slot {
        case .lead:
            return startLead(lead.job == .conversation ? .planning : lead.job, at: now, fresh: lead.task == nil)
        case .assignment(let id):
            guard let index = assignmentIndex(id) else { return [] }
            if assignments[index].assignment.continues == nil {
                assignments[index].task = nil
            }
            assignments[index].goal = nil
            assignments[index].turns = 0
            assignments[index].automaticRecoveries = 0
            return begin(index, at: now)
        case .checkpoint(let leg):
            guard let index = checkpointIndex(leg) else { return [] }
            return beginCheckpoint(index, at: now)
        }
    }
}

extension TurnOutcome {
    /// What a seat's status becomes when its turn ends this way.
    var stoppedStatus: WorkflowStepStatus {
        switch self {
        case .ended: .succeeded
        case .cancelled: .cancelled
        case .limited(let message): .limited(message)
        case .refused: .failed("The agent declined to continue.")
        case .failed(let message): .failed(message)
        }
    }

    var summary: String {
        switch self {
        case .ended: "finished"
        case .cancelled: "stopped"
        case .limited(let message), .failed(let message): message
        case .refused: "the agent declined to continue"
        }
    }
}

enum LimitText {
    static let continuation = "Continue where you left off."
}
