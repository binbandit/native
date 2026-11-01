import ACP
import Foundation
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
        let current: [SessionSummary]
        var earlier: [SessionSummary] = []
        var isEarlierExpanded = false
        var visible: [SessionSummary] { current + (isEarlierExpanded ? earlier : []) }
    }

    let filter: TaskFilter
    /// Every pinned task, in pin order.
    let allPinned: [SessionSummary]
    let pinned: [SessionSummary]
    let groups: [Group]

    init(
        model: AppModel, filter: TaskFilter, insights: SidebarTaskInsights,
        folding: SidebarDayFolding? = nil, now: Date = .now
    ) {
        self.filter = filter
        allPinned = model.pinnedSessions
        let facts = { (summary: SessionSummary) in model.taskFacts(for: summary, insights: insights) }
        let filteredPinned = filter.isActive ? filter.apply(to: allPinned, facts: facts) : allPinned
        let raw = model.taskGroups.map { project in
            let all = model.sessions(in: project.id)
            let candidates = filter.includesArchived ? all + model.archivedSessions(in: project.id) : all
            return Group(
                project: project, all: all,
                current: filter.isActive ? filter.apply(to: candidates, facts: facts) : all)
        }
        let grouped = model.groupTaskPairs(model.groupCoordinatorTasks([filteredPinned] + raw.map(\.visible)))
        pinned = grouped[0]
        groups = raw.enumerated().map { index, group in
            let candidates = grouped[index + 1]
            guard let folding, !filter.isNarrowing else {
                return Group(project: group.project, all: group.all, current: candidates)
            }
            let parts = TaskDayFolding.partition(candidates) { summary in
                let status = TaskStatus(model.session(summary.id))
                return TaskDayFolding.isEarlier(
                    lastActivity: model.lastActivity(for: summary),
                    isAtRest: status == .done || status == .idle || status == .cancelled,
                    isUnread: model.isUnread(summary.id),
                    isProtected: model.removedWorkspaces[summary.id] != nil
                        || model.remotePlace(of: summary.id)?.host.isOnline == false
                        || (!folding.isExpanded(group.project.id)
                            && (summary.id == model.renaming || summary.id == model.taskPeek.request?.task)),
                    interval: model.sidebarPreferences.foldAfter, now: now)
            } isChild: {
                model.isCoordinatorChild($0.id, among: candidates)
            }
            return Group(
                project: group.project, all: group.all, current: parts.current, earlier: parts.earlier,
                isEarlierExpanded: folding.isExpanded(group.project.id))
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
