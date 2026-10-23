import ACP
import NativeOrchestration
import TaskList

/// The sidebar's tasks as the window's filter shows them, worked out once per update: the pinned
/// ones and each project's, filtered and sorted by `TaskFilter`. With no filter on, the lists are
/// the model's own, untouched.
struct SidebarListing {
    struct Group {
        let project: Project
        /// Every task in the project's order, for moving rows.
        let all: [SessionSummary]
        /// What the filter keeps, in its order; archived tasks too when the filter includes them.
        let visible: [SessionSummary]
    }

    let filter: TaskFilter
    /// Every pinned task, in pin order.
    let allPinned: [SessionSummary]
    let pinned: [SessionSummary]
    let groups: [Group]

    init(model: AppModel, filter: TaskFilter, insights: SidebarTaskInsights) {
        self.filter = filter
        allPinned = model.pinnedSessions
        let facts = { (summary: SessionSummary) in model.taskFacts(for: summary, insights: insights) }
        let filteredPinned = filter.isActive ? filter.apply(to: allPinned, facts: facts) : allPinned
        let raw = model.projects.all.map { project in
            let all = model.sessions(in: project.id)
            let candidates = filter.includesArchived ? all + model.archivedSessions(in: project.id) : all
            return Group(
                project: project, all: all,
                visible: filter.isActive ? filter.apply(to: candidates, facts: facts) : all)
        }
        if model.offersCoordinatorTasks {
            let lists = [filteredPinned] + raw.map(\.visible)
            let lookup = Dictionary(lists.flatMap { $0 }.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
            let assignments = Dictionary(
                uniqueKeysWithValues: model.coordinators.map { record in
                    (
                        SessionKey(
                            agent: AgentDefinition.ID(rawValue: record.task.agentID), id: record.task.agentSessionID),
                        record.assignments.map {
                            SessionKey(agent: AgentDefinition.ID(rawValue: $0.agentID), id: $0.agentSessionID)
                        }
                    )
                })
            let grouped = CoordinatorOrdering.grouped(lists.map { $0.map(\.id) }, assignments: assignments)
            pinned = grouped[0].compactMap { lookup[$0] }
            groups = raw.enumerated().map { index, group in
                Group(project: group.project, all: group.all, visible: grouped[index + 1].compactMap { lookup[$0] })
            }
        } else {
            pinned = filteredPinned
            groups = raw
        }
    }

    /// The tasks on screen, top to bottom, for ⇧-click runs.
    var order: [SessionKey] {
        (pinned + groups.flatMap(\.visible)).map(\.id)
    }

    /// Whether the filter leaves nothing to show anywhere.
    var isEmpty: Bool {
        pinned.isEmpty && groups.allSatisfy(\.visible.isEmpty)
    }
}

extension AppModel {
    /// A task as the sidebar's filters see it.
    func taskFacts(for summary: SessionSummary, insights: SidebarTaskInsights) -> TaskFacts {
        let session = session(summary.id)
        return TaskFacts(
            activity: TaskFacts.Activity(session),
            isUnread: isUnread(summary.id),
            agent: summary.agent.id.rawValue,
            hasUncommittedChanges: insights.hasUncommittedChanges(summary),
            hasPullRequest: insights.hasPullRequest(summary),
            isArchived: isArchived(summary.id),
            title: title(for: summary),
            lastActivity: lastActivity(for: summary)
        )
    }
}

extension TaskFacts.Activity {
    /// Where an open session stands, for the filters and sorts, from the status every surface reads
    /// (`SessionModel.taskStatus`); one that isn't open in this run is idle.
    init(_ session: SessionModel?) {
        self =
            switch session?.taskStatus ?? .idle {
            case .needsInput, .needsPermission, .needsPlanReview: .needsYou
            case .starting, .working, .waiting: .running
            case .failed: .failed
            case .done: .done
            // A stopped turn is at rest, as the user left it.
            case .idle, .cancelled, .paused, .limited: .idle
            }
    }
}
