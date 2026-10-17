import Foundation
import NativeAutomation

extension Expedition {
    /// Starts whatever can run now: the current leg's assignments as their dependencies finish, up
    /// to the parallel limit; its checkpoint once they're all done; the debrief once every leg is.
    /// Later legs wait for the current one, and nothing new goes out while the expedition is held.
    mutating func advance(at now: Date) -> [ExpeditionEffect] {
        guard approvedAt != nil, !isStopped, endedAt == nil, pendingRouteChange == nil, base != nil, let route else {
            return []
        }
        if legsSettled {
            return isPaused ? [] : beginDebrief(at: now)
        }
        guard !isHeld(at: now) else { return [] }
        if case .reviewingLeg = lead.job, lead.status.isActive { return [] }
        for leg in route.legs {
            guard let checkpoint = checkpointIndex(leg.id), !checkpoints[checkpoint].status.isFinished else { continue }
            var effects: [ExpeditionEffect] = []
            var active = assignments.count { $0.status.isActive }
            for index in assignments.indices
            where assignments[index].leg == leg.id && assignments[index].status == .waiting {
                guard active < settings.maxParallel else { break }
                guard assignments[index].assignment.after.allSatisfy({ assignment($0)?.status.isFinished ?? true })
                else { continue }
                effects += begin(index, at: now)
                active += 1
            }
            let runs = assignments(in: leg.id)
            if runs.allSatisfy(\.status.isFinished), checkpoints[checkpoint].status == .waiting {
                if runs.allSatisfy({ $0.status == .skipped }) {
                    // Nothing was built, so there's nothing to check.
                    checkpoints[checkpoint].status = .skipped
                    continue
                }
                effects += beginCheckpoint(checkpoint, at: now)
            }
            return effects
        }
        return legsSettled ? beginDebrief(at: now) : []
    }

    /// Paused by the user or out of budget: turns in flight finish, nothing new goes out.
    func isHeld(at now: Date) -> Bool {
        isPaused || exhaustedBudget(at: now) != nil
    }

    /// Sends the next prompt of every assignment a hold stopped between turns.
    mutating func releaseHeld(at now: Date) -> [ExpeditionEffect] {
        guard !isHeld(at: now) else { return [] }
        return assignments.indices.filter { assignments[$0].status == .paused }.flatMap { sendGoalPrompt($0, at: now) }
    }

    // MARK: - Starting seats

    mutating func begin(_ index: Int, at now: Date) -> [ExpeditionEffect] {
        let run = assignments[index]
        let slot = CrewSlot.assignment(run.id)
        let source = run.assignment.continues.flatMap(assignment)
        assignments[index].status = .starting
        assignments[index].startedAt = now
        assignments[index].endedAt = nil
        assignments[index].waitingSince = nil
        let objective =
            run.isFix
            ? leg(run.leg).map(ExpeditionPrompt.fixGoal) ?? run.assignment.title : ExpeditionPrompt.assignmentGoal(run)
        assignments[index].goal = GoalLoop(
            objective: objective, budget: GoalBudget(maxIterations: settings.assignmentIterations), at: now,
            sessionCost: source?.sessionCost)
        if let source, let task = source.task {
            // A fix round continues the builder's session, so it keeps what it learned.
            assignments[index].task = task
            assignments[index].costBaseline = source.sessionCost
            assignments[index].sessionCost = source.sessionCost
            return sendGoalPrompt(index, at: now)
        }
        guard let base else { return [] }
        return [.createTask(slot, agent: agent(of: slot), title: run.assignment.title, cwd: base)]
    }

    mutating func beginCheckpoint(_ index: Int, at now: Date) -> [ExpeditionEffect] {
        let leg = checkpoints[index].leg
        guard let legInfo = self.leg(leg), let base else { return [] }
        checkpoints[index].status = .starting
        checkpoints[index].startedAt = checkpoints[index].startedAt ?? now
        checkpoints[index].endedAt = nil
        checkpoints[index].waitingSince = nil
        guard checkpoints[index].task != nil else {
            return [.createTask(.checkpoint(leg), agent: crew.reviewer, title: "Check “\(legInfo.title)”", cwd: base)]
        }
        let text =
            checkpoints[index].rounds == 0
            ? ExpeditionPrompt.checkpoint(self, leg: legInfo)
            : ExpeditionPrompt.recheck(self, leg: legInfo, fix: assignments(in: leg).last { $0.isFix })
        return send(text, to: .checkpoint(leg), at: now)
    }

    /// Adds a round of fixes for the findings in `verdict`, for the builder whose work the leg
    /// finished with, in its own session. The checkpoint runs again once it's done.
    mutating func startFixRound(_ index: Int, verdict: CheckpointVerdict, at now: Date) -> [ExpeditionEffect] {
        let leg = checkpoints[index].leg
        guard let legInfo = self.leg(leg) else { return [] }
        let built = assignments(in: leg).filter { $0.status == .succeeded }
        let source =
            built.max { ($0.endedAt ?? .distantPast) < ($1.endedAt ?? .distantPast) } ?? assignments(in: leg).last
        let round = checkpoints[index].rounds
        let fix = Route.Assignment(
            id: "\(leg)-fix-\(round)",
            title: "Fix the checkpoint’s findings (round \(round))",
            brief: ExpeditionPrompt.fixBriefing(self, leg: legInfo, verdict: verdict, round: round),
            doneWhen: ["Every problem the reviewer listed is fixed", legInfo.outcome],
            assignee: source?.assignment.assignee ?? crew.builders[0].id,
            continues: source?.id
        )
        let position = (assignments.lastIndex { $0.leg == leg } ?? assignments.count - 1) + 1
        assignments.insert(AssignmentRun(assignment: fix, leg: leg, fixRound: round), at: position)
        checkpoints[index].status = .waiting
        checkpoints[index].endedAt = nil
        checkpoints[index].waitingSince = nil
        return advance(at: now)
    }

    /// Asks the lead to look at the legs ahead, when there are any and it's set to; otherwise goes on.
    mutating func afterCheckpointPassed(_ leg: Route.Leg, at now: Date) -> [ExpeditionEffect] {
        let ahead = route?.legs.drop { $0.id != leg.id }.dropFirst() ?? []
        if settings.consultsLeadBetweenLegs, !ahead.isEmpty, !isWrappingUp, lead.task != nil, !lead.status.isActive {
            lead.job = .reviewingLeg(leg.id)
            return send(ExpeditionPrompt.legReview(self, passed: leg), to: .lead, at: now)
        }
        return advance(at: now)
    }

    private mutating func beginDebrief(at now: Date) -> [ExpeditionEffect] {
        guard debrief == nil, lead.job != .debriefing || !(lead.status.isActive || lead.status.isStopped) else {
            return []
        }
        note(.progress, "Every leg is done. \(crew.lead.name) is writing the debrief.", slot: .lead, at: now)
        return startLead(.debriefing, at: now)
    }

    mutating func startLead(_ job: LeadRun.Job, at now: Date, fresh: Bool = false) -> [ExpeditionEffect] {
        lead.job = job
        lead.waitingSince = nil
        if lead.task != nil, !fresh {
            return send(leadPrompt(), to: .lead, at: now)
        }
        guard let base else { return [] }
        lead.status = .starting
        return [.createTask(.lead, agent: crew.lead, title: "Lead: \(title)", cwd: base)]
    }

    func leadPrompt() -> String {
        switch lead.job {
        case .planning: ExpeditionPrompt.planning(self)
        case .revising: ExpeditionPrompt.revision(feedback: feedback ?? "")
        case .reviewingLeg(let id):
            leg(id).map { ExpeditionPrompt.legReview(self, passed: $0) } ?? LimitText.continuation
        case .debriefing: ExpeditionPrompt.debrief(self)
        case .conversation: LimitText.continuation
        }
    }

    // MARK: - Turns going out

    /// The assignment's next goal prompt, with its briefing first when the agent hasn't heard about
    /// the work yet.
    mutating func sendGoalPrompt(_ index: Int, at now: Date, prefix: String? = nil) -> [ExpeditionEffect] {
        let slot = CrewSlot.assignment(assignments[index].id)
        guard let loop = assignments[index].goal, let next = loop.nextPrompt(at: now) else {
            return send(prefix ?? LimitText.continuation, to: slot, at: now)
        }
        var parts = [
            prefix, loop.needsKickoff ? ExpeditionPrompt.assignmentBriefing(self, assignments[index]) : nil, next,
        ].compactMap(\.self)
        if assignments[index].isFix, loop.needsKickoff {
            parts = [prefix, assignments[index].assignment.brief, next].compactMap(\.self)
        }
        return send(parts.joined(separator: "\n\n"), to: slot, at: now, origin: .goal)
    }

    /// Marks the seat working and hands its session `text` as the next prompt.
    mutating func send(
        _ text: String, to slot: CrewSlot, at now: Date, origin: GoalLoop.Origin = .goal
    ) -> [ExpeditionEffect] {
        guard let task = task(of: slot) else { return [] }
        switch slot {
        case .lead:
            lead.status = .running
            lead.waitingSince = nil
        case .assignment(let id):
            guard let index = assignmentIndex(id) else { return [] }
            assignments[index].status = .running
            assignments[index].startedAt = assignments[index].startedAt ?? now
            assignments[index].endedAt = nil
            assignments[index].waitingSince = nil
            assignments[index].goal?.turnWillStart(origin, at: now)
        case .checkpoint(let leg):
            guard let index = checkpointIndex(leg) else { return [] }
            checkpoints[index].status = .running
            checkpoints[index].endedAt = nil
            checkpoints[index].waitingSince = nil
        }
        return [.prompt(slot, task: task, text: text)]
    }

    /// Stops a seat short, waiting for the user.
    mutating func stop(_ slot: CrewSlot, as status: WorkflowStepStatus, at now: Date) {
        set(slot, status: status, at: now)
        switch slot {
        case .lead: lead.waitingSince = now
        case .assignment(let id): assignmentIndex(id).map { assignments[$0].waitingSince = now }
        case .checkpoint(let leg): checkpointIndex(leg).map { checkpoints[$0].waitingSince = now }
        }
    }

    mutating func set(_ slot: CrewSlot, status: WorkflowStepStatus, at now: Date) {
        switch slot {
        case .lead:
            lead.status = status
            lead.waitingSince = nil
        case .assignment(let id):
            guard let index = assignmentIndex(id) else { return }
            assignments[index].status = status
            assignments[index].endedAt = now
            assignments[index].waitingSince = nil
        case .checkpoint(let leg):
            guard let index = checkpointIndex(leg) else { return }
            checkpoints[index].status = status
            checkpoints[index].endedAt = now
            checkpoints[index].waitingSince = nil
        }
    }

    /// Makes an assignment's goal active again, granting a spent iteration budget once more.
    mutating func resumeGoal(_ slot: CrewSlot, at now: Date) {
        guard case .assignment(let id) = slot, let index = assignmentIndex(id), var loop = assignments[index].goal
        else { return }
        if !loop.resume(at: now) {
            loop.extendBudget(at: now)
            loop.resume(at: now)
        }
        assignments[index].goal = loop
    }

    // MARK: - The route

    /// Makes the assignments and checkpoints match `route`. Work that has started keeps its run;
    /// work that hasn't takes the route's version; fix rounds stay with their legs.
    mutating func sync(to route: Route) {
        self.route = route
        var runs: [AssignmentRun] = []
        for leg in route.legs {
            for planned in leg.assignments {
                if var existing = assignment(planned.id), existing.leg == leg.id || existing.status != .waiting {
                    if existing.status == .waiting {
                        existing.assignment = planned
                    }
                    runs.append(existing)
                } else {
                    runs.append(AssignmentRun(assignment: planned, leg: leg.id))
                }
            }
            runs += assignments.filter { $0.leg == leg.id && $0.isFix }
        }
        // Started work the route no longer lists keeps its record.
        runs += assignments.filter { run in run.status != .waiting && !runs.contains { $0.id == run.id } }
        assignments = runs
        checkpoints = route.legs.map { checkpoint($0.id) ?? CheckpointRun(leg: $0.id) }
    }

    func assignmentIndex(_ id: String) -> Int? {
        assignments.firstIndex { $0.id == id }
    }

    func checkpointIndex(_ leg: String) -> Int? {
        checkpoints.firstIndex { $0.leg == leg }
    }
}
