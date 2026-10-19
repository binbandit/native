import Foundation

/// The sidebar's filters and sort. Choices within a group widen the list (Codex or Claude Code;
/// Needs You or Running), the groups narrow it together (Codex and Needs You), and the checkout
/// filters each narrow it on their own. Archived tasks stay out unless `includesArchived`.
/// Codable, so a window can keep its filters across launches.
public struct TaskFilter: Codable, Hashable, Sendable {
    public enum Status: String, Codable, CaseIterable, Sendable {
        case needsYou, running, unread, done, failed

        public var title: String {
            switch self {
            case .needsYou: "Needs you"
            case .running: "Running"
            case .unread: "Unread"
            case .done: "Done"
            case .failed: "Failed"
            }
        }
    }

    public enum Sort: String, Codable, CaseIterable, Sendable {
        /// The list's own order: the user's arrangement, then the most recently active first.
        case recent
        /// By title, as the Finder sorts names.
        case name
        /// Most urgent first (`TaskFacts.Activity`), then the list's own order.
        case status

        public var title: String {
            switch self {
            case .recent: "Recent activity"
            case .name: "Name"
            case .status: "Status"
            }
        }
    }

    /// One active filter, as a removable chip shows it.
    public enum Chip: Hashable, Sendable {
        case status(Status)
        case agent(String)
        case uncommittedChanges
        case pullRequest
        case archived
    }

    public var statuses: Set<Status>
    /// Agent ids.
    public var agents: Set<String>
    public var requiresUncommittedChanges: Bool
    public var requiresPullRequest: Bool
    public var includesArchived: Bool
    public var sort: Sort

    public init(
        statuses: Set<Status> = [], agents: Set<String> = [], requiresUncommittedChanges: Bool = false,
        requiresPullRequest: Bool = false, includesArchived: Bool = false, sort: Sort = .recent
    ) {
        self.statuses = statuses
        self.agents = agents
        self.requiresUncommittedChanges = requiresUncommittedChanges
        self.requiresPullRequest = requiresPullRequest
        self.includesArchived = includesArchived
        self.sort = sort
    }

    /// Whether anything leaves tasks out of the list. Including archived ones and sorting don't.
    public var isNarrowing: Bool {
        !statuses.isEmpty || !agents.isEmpty || requiresUncommittedChanges || requiresPullRequest
    }

    /// Whether the list differs from the unfiltered one at all.
    public var isActive: Bool {
        isNarrowing || includesArchived || sort != .recent
    }

    /// The active filters in a stable order: statuses, agents (by id), then the rest. Sorting isn't
    /// a chip; the menu shows it.
    public var chips: [Chip] {
        Status.allCases.filter(statuses.contains).map(Chip.status)
            + agents.sorted().map(Chip.agent)
            + (requiresUncommittedChanges ? [.uncommittedChanges] : [])
            + (requiresPullRequest ? [.pullRequest] : [])
            + (includesArchived ? [.archived] : [])
    }

    public mutating func remove(_ chip: Chip) {
        switch chip {
        case .status(let status): statuses.remove(status)
        case .agent(let agent): agents.remove(agent)
        case .uncommittedChanges: requiresUncommittedChanges = false
        case .pullRequest: requiresPullRequest = false
        case .archived: includesArchived = false
        }
    }

    /// Clears every filter, keeping the sort.
    public mutating func clearFilters() {
        let sort = sort
        self = TaskFilter(sort: sort)
    }

    public mutating func toggle(_ status: Status) {
        if statuses.remove(status) == nil { statuses.insert(status) }
    }

    public mutating func toggle(agent: String) {
        if agents.remove(agent) == nil { agents.insert(agent) }
    }

    public func matches(_ task: TaskFacts) -> Bool {
        if task.isArchived, !includesArchived { return false }
        if !statuses.isEmpty, !statuses.contains(where: { $0.matches(task) }) { return false }
        if !agents.isEmpty, !agents.contains(task.agent) { return false }
        if requiresUncommittedChanges, !task.hasUncommittedChanges { return false }
        if requiresPullRequest, !task.hasPullRequest { return false }
        return true
    }

    /// The tasks that match, in the sort's order. `facts` describes each task; ties keep the order
    /// they came in.
    public func apply<Task>(to tasks: [Task], facts: (Task) -> TaskFacts) -> [Task] {
        let matching = tasks.map { ($0, facts($0)) }.filter { matches($0.1) }
        let sorted: [(Task, TaskFacts)] =
            switch sort {
            case .recent: matching
            case .name:
                matching.enumerated().sorted { lhs, rhs in
                    let order = lhs.element.1.title.localizedStandardCompare(rhs.element.1.title)
                    return order == .orderedSame ? lhs.offset < rhs.offset : order == .orderedAscending
                }
                .map(\.element)
            case .status:
                matching.enumerated().sorted { lhs, rhs in
                    lhs.element.1.activity == rhs.element.1.activity
                        ? lhs.offset < rhs.offset : lhs.element.1.activity < rhs.element.1.activity
                }
                .map(\.element)
            }
        return sorted.map(\.0)
    }
}

extension TaskFilter.Status {
    func matches(_ task: TaskFacts) -> Bool {
        switch self {
        case .needsYou: task.activity == .needsYou
        case .running: task.activity == .running
        case .unread: task.isUnread
        case .done: task.activity == .done
        case .failed: task.activity == .failed
        }
    }
}
