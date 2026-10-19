import ACP
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
        guard filter.isActive else {
            pinned = allPinned
            groups = model.projects.all.map { project in
                let all = model.sessions(in: project.id)
                return Group(project: project, all: all, visible: all)
            }
            return
        }
        let facts = { (summary: SessionSummary) in model.taskFacts(for: summary, insights: insights) }
        pinned = filter.apply(to: allPinned, facts: facts)
        groups = model.projects.all.map { project in
            let all = model.sessions(in: project.id)
            let candidates = filter.includesArchived ? all + model.archivedSessions(in: project.id) : all
            return Group(project: project, all: all, visible: filter.apply(to: candidates, facts: facts))
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
            lastActivity: session?.lastActivity ?? summary.info.updatedDate
        )
    }
}

extension TaskFacts.Activity {
    /// Where an open session stands; one that isn't open in this run is idle.
    init(_ session: SessionModel?) {
        guard let session else {
            self = .idle
            return
        }
        if session.wait != nil || session.needsApproval {
            self = .needsYou
            return
        }
        switch session.phase {
        case .loading, .prompting: self = .running
        case .disconnected: self = .failed
        case .idle:
            switch session.lastStopReason {
            case .endTurn, .maxTokens, .maxTurnRequests: self = .done
            case .refusal, .error: self = .failed
            case .cancelled, .other, nil: self = .idle
            }
        }
    }
}
