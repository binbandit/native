import Foundation

/// A task that starts itself: when (its triggers), what (its action), on which agent, in which
/// project, and where in it.
nonisolated struct Automation: Codable, Hashable, Sendable, Identifiable {
    let id: UUID
    var name: String
    var triggers: [AutomationTrigger]
    var action: AutomationAction
    /// The agent steps run on unless a workflow says otherwise; nil uses the default agent.
    var agent: WorkflowAgent.ID?
    var project: URL
    /// The project's GitHub repository (`owner/name`), for matching pull request events.
    var repository: String?
    var placement: AutomationPlacement
    var isPaused: Bool
    let createdAt: Date

    init(
        id: UUID = UUID(), name: String, triggers: [AutomationTrigger], action: AutomationAction, agent: WorkflowAgent.ID? = nil,
        project: URL, repository: String? = nil, placement: AutomationPlacement = .worktree, isPaused: Bool = false, createdAt: Date
    ) {
        self.id = id
        self.name = name
        self.triggers = triggers
        self.action = action
        self.agent = agent
        self.project = project
        self.repository = repository
        self.placement = placement
        self.isPaused = isPaused
        self.createdAt = createdAt
    }

    var schedules: [AutomationSchedule] {
        triggers.compactMap { if case .schedule(let schedule) = $0 { schedule } else { nil } }
    }

    var eventKinds: Set<AutomationEventKind> {
        Set(triggers.compactMap { if case .event(let kind) = $0 { kind } else { nil } })
    }

    /// The next scheduled time after `date`, if it has a schedule and isn't paused.
    func nextFire(after date: Date) -> Date? {
        guard !isPaused else { return nil }
        return schedules.map { $0.nextFire(after: date, anchor: createdAt) }.min()
    }

    /// Whether `occurrence` should start it: the event is one it waits for, in its project.
    func matches(_ occurrence: AutomationOccurrence) -> Bool {
        guard !isPaused, eventKinds.contains(occurrence.kind) else { return false }
        if let repository = occurrence.repository {
            return repository.caseInsensitiveCompare(self.repository ?? "") == .orderedSame
        }
        return occurrence.project.map(Self.folderPath) == Self.folderPath(project)
    }

    /// A folder's path without a trailing slash, so "/work/app" and "/work/app/" match.
    private static func folderPath(_ url: URL) -> String {
        let path = url.standardizedFileURL.path(percentEncoded: false)
        return path.count > 1 && path.hasSuffix("/") ? String(path.dropLast()) : path
    }
}
