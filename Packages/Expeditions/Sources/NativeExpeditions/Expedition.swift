import Foundation
import NativeAutomation

/// An expedition, and its state machine: a crew working through a route the user approved. Like
/// `WorkflowRun` it never touches an agent: events go in, effects for the host come out
/// (`handle(_:at:)`), so planning, scheduling, checkpoints, budgets and recovery are all testable
/// without sessions.
///
/// The lead plans and revises; Native's engine, not the lead, decides what runs next. Legs run in
/// order, assignments within a leg as their dependencies finish, each driven as a goal; a leg's
/// checkpoint runs once its assignments are done, and asks for fix rounds until it passes or its
/// rounds run out. Then the lead writes the debrief and the pull request opens.
public nonisolated struct Expedition: Codable, Hashable, Sendable, Identifiable {
    public let id: UUID
    /// What the user wants done, in their words.
    public let objective: String
    public let title: String
    /// The project the expedition is about.
    public let project: URL
    /// Whether the crew works in a worktree of its own, or in the project folder itself.
    public let usesWorktree: Bool
    public let createdAt: Date
    public internal(set) var crew: Crew
    public internal(set) var budget: ExpeditionBudget
    public let settings: ExpeditionSettings

    /// Where the crew works; nil until it's made.
    public internal(set) var base: URL?
    public internal(set) var baseError: String?
    /// The route on the table: proposed, or approved and being worked through.
    public internal(set) var route: Route?
    /// Routes the lead proposed before this one, oldest first, so a revision can show what changed.
    public internal(set) var previousRoutes: [Route] = []
    public internal(set) var approvedAt: Date?
    /// The lead's revision of the legs ahead, waiting for the user because it changes approved work.
    public internal(set) var pendingRouteChange: Route?
    /// The user's latest note on the route, for the lead's revision.
    public internal(set) var feedback: String?
    public internal(set) var lead = LeadRun()
    public internal(set) var assignments: [AssignmentRun] = []
    public internal(set) var checkpoints: [CheckpointRun] = []
    public internal(set) var log: [LogbookEntry] = []
    public internal(set) var debrief: String?
    public internal(set) var pullRequest: WorkflowPullRequestResult?
    public internal(set) var pullRequestError: String?
    public internal(set) var isOpeningPullRequest = false
    public internal(set) var isPaused = false
    public internal(set) var isStopped = false
    public internal(set) var isWrappingUp = false
    public internal(set) var endedAt: Date?
    public internal(set) var updatedAt: Date
    /// Wall time with any member working, banked before the current stretch.
    public internal(set) var bankedActive: TimeInterval = 0
    public internal(set) var activeSince: Date?

    public init(
        id: UUID = UUID(), objective: String, project: URL, usesWorktree: Bool, crew: Crew,
        budget: ExpeditionBudget = .unlimited,
        settings: ExpeditionSettings = ExpeditionSettings(), at now: Date
    ) {
        self.id = id
        self.objective = objective.trimmed
        title = Self.title(for: self.objective)
        self.project = project
        self.usesWorktree = usesWorktree
        self.crew = crew
        self.budget = budget
        self.settings = settings
        createdAt = now
        updatedAt = now
    }

    /// The first line of the objective, shortened for a title bar.
    public static func title(for objective: String) -> String {
        let line = objective.split(whereSeparator: \.isNewline).first.map(String.init)?.trimmed ?? ""
        guard !line.isEmpty else { return "Untitled expedition" }
        return line.count > 72 ? String(line.prefix(71)) + "…" : line
    }

    // MARK: - Queries

    public func assignment(_ id: String) -> AssignmentRun? {
        assignments.first { $0.id == id }
    }

    public func checkpoint(_ leg: String) -> CheckpointRun? {
        checkpoints.first { $0.leg == leg }
    }

    public func leg(_ id: String) -> Route.Leg? {
        route?.legs.first { $0.id == id }
    }

    /// The assignments of `leg`, fix rounds included, in order.
    public func assignments(in leg: String) -> [AssignmentRun] {
        assignments.filter { $0.leg == leg }
    }

    /// The seat whose turn is running in `task`. Sessions can be shared (a fix round continues a
    /// builder's), but only one seat uses a session at a time.
    public func slot(forTask task: UUID) -> CrewSlot? {
        if lead.task == task, lead.status.isActive { return .lead }
        if let run = assignments.last(where: { $0.task == task && $0.status.isActive }) { return .assignment(run.id) }
        if let run = checkpoints.first(where: { $0.task == task && $0.status.isActive }) { return .checkpoint(run.leg) }
        return nil
    }

    /// Every session the crew has used, for whoever needs to find them.
    public var tasks: [UUID] {
        var seen = Set<UUID>()
        return ([lead.task] + assignments.map(\.task) + checkpoints.map(\.task)).compactMap(\.self).filter {
            seen.insert($0).inserted
        }
    }

    public func status(of slot: CrewSlot) -> WorkflowStepStatus? {
        switch slot {
        case .lead: lead.status
        case .assignment(let id): assignment(id)?.status
        case .checkpoint(let leg): checkpoint(leg)?.status
        }
    }

    public func task(of slot: CrewSlot) -> UUID? {
        switch slot {
        case .lead: lead.task
        case .assignment(let id): assignment(id)?.task
        case .checkpoint(let leg): checkpoint(leg)?.task
        }
    }

    /// The agent in a seat.
    public func agent(of slot: CrewSlot) -> WorkflowAgent {
        switch slot {
        case .lead: crew.lead
        case .checkpoint: crew.reviewer
        case .assignment(let id):
            assignment(id).flatMap { crew.agent($0.assignment.assignee) }
                ?? WorkflowAgent(
                    id: assignment(id)?.assignment.assignee ?? "",
                    name: assignment(id)?.assignment.assignee ?? "An agent")
        }
    }

    /// What the seat is called in the overview and the logbook.
    public func name(of slot: CrewSlot) -> String {
        switch slot {
        case .lead: "The lead"
        case .assignment(let id): "“\(assignment(id)?.assignment.title ?? id)”"
        case .checkpoint(let leg): "The checkpoint for “\(self.leg(leg)?.title ?? leg)”"
        }
    }

    /// What the crew has spent, across every session that reported cost.
    public var cost: Double? {
        let costs =
            assignments.compactMap(\.cost) + checkpoints.compactMap(\.sessionCost)
            + [lead.sessionCost].compactMap(\.self)
        return costs.isEmpty ? nil : costs.reduce(0, +)
    }

    public func activeTime(at now: Date) -> TimeInterval {
        bankedActive + (activeSince.map { max(0, now.timeIntervalSince($0)) } ?? 0)
    }

    /// Why the expedition's budget is used up, if it is.
    public func exhaustedBudget(at now: Date) -> String? {
        budget.exhausted(cost: cost, active: activeTime(at: now))
    }

    public var finishedCount: Int {
        assignments.count { $0.status.isFinished }
    }

    /// The leg being worked on: the first whose checkpoint hasn't passed.
    public var currentLeg: Route.Leg? {
        route?.legs.first { checkpoint($0.id)?.status.isFinished != true }
    }

    var isAnyoneWorking: Bool {
        lead.status.isActive || assignments.contains { $0.status.isActive }
            || checkpoints.contains { $0.status.isActive }
    }

    /// Every leg's checkpoint has passed or been skipped: the debrief comes next.
    var legsSettled: Bool {
        approvedAt != nil && !checkpoints.isEmpty && checkpoints.allSatisfy(\.status.isFinished)
            && !assignments.contains { $0.status.isActive }
    }

    public var phase: ExpeditionPhase {
        if isStopped { return .stopped }
        if endedAt != nil { return .complete }
        if baseError != nil { return .needsYou }
        guard approvedAt != nil else {
            if lead.status.isActive || lead.status == .waiting { return .planning }
            if lead.status == .succeeded, route != nil { return .reviewing }
            if case .limited = lead.status { return .limited }
            return .needsYou
        }
        if legsSettled {
            if pullRequestError != nil { return .needsYou }
            if case .limited = lead.status { return .limited }
            return lead.status.isStopped ? .needsYou : .debriefing
        }
        if isPaused { return .paused }
        let items = attention
        if items.isEmpty { return .underway }
        return items.allSatisfy(\.isLimit) ? .limited : .needsYou
    }

    /// The item waiting on the user the longest; it answers the approval shortcuts.
    public var oldestAttention: ExpeditionAttention? {
        attention.min { $0.since < $1.since }
    }
}
