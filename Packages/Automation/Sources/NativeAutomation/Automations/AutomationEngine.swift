import Foundation
import Observation

/// Automations, live: saves and edits them, wakes up when one is due, polls GitHub for the events
/// they wait on, starts their runs as workflow runs and follows those runs to an outcome. The rules
/// are `AutomationPlanner`'s and `AutomationEventDetector`'s; this adds the clock, the host and
/// storage.
@MainActor
@Observable
public final class AutomationEngine {
    public private(set) var book: AutomationBook {
        didSet { store?.save(book) }
    }

    /// Where runs happen. Setting it starts the schedule.
    @ObservationIgnored public var host: (any AutomationHost)? {
        didSet { reconcileOpenRuns(); reschedule() }
    }
    /// Off while the Automations plugin is off: nothing fires and nothing is polled.
    @ObservationIgnored public var isEnabled = true {
        didSet { reschedule() }
    }
    /// Why pull request events can't be seen right now, if they can't; nil once a poll works.
    public private(set) var eventSourceProblem: String?

    @ObservationIgnored private let store: AutomationStore?
    @ObservationIgnored private let now: () -> Date
    @ObservationIgnored private var loop: Task<Void, Never>?
    @ObservationIgnored private var lastPoll: Date?

    /// How often GitHub is asked about pull requests while an automation waits on one. gh's search
    /// budget is 30 a minute and the inbox costs three, so this leaves room for everything else.
    public static let pollInterval: TimeInterval = 120

    public init(store: AutomationStore? = nil, now: @escaping () -> Date = Date.init) {
        self.store = store
        self.now = now
        book = store?.load() ?? AutomationBook()
    }

    public var automations: [Automation] {
        book.automations
    }

    public func runs(of id: Automation.ID) -> [AutomationRun] {
        book.runs(of: id)
    }

    /// The next scheduled run of `automation`, for the list.
    public func nextFire(of automation: Automation) -> Date? {
        automation.nextFire(after: max(book.lastChecked[automation.id] ?? automation.createdAt, now()))
    }

    // MARK: - User actions

    public func save(_ automation: Automation) async {
        var automation = automation
        automation.repository = await host?.repository(of: automation.project) ?? automation.repository
        if book.automation(automation.id) == nil {
            // A new automation's schedule starts now, not at some earlier anchor.
            book.lastChecked[automation.id] = now()
        }
        book.save(automation)
        reschedule()
    }

    public func delete(_ id: Automation.ID) {
        if let run = book.openRun(of: id)?.workflowRun {
            host?.cancelWorkflowRun(run)
        }
        book.delete(id)
        reschedule()
    }

    public func setPaused(_ paused: Bool, for id: Automation.ID) {
        guard var automation = book.automation(id) else { return }
        automation.isPaused = paused
        book.save(automation)
        if !paused {
            // Times that passed while paused were skipped on purpose; don't make them up now.
            book.lastChecked[id] = now()
        }
        reschedule()
    }

    public func runNow(_ id: Automation.ID) {
        fire(id, reason: .manual)
    }

    public func stop(_ id: AutomationRun.ID) {
        guard let run = book.runs.first(where: { $0.id == id }), run.status.isOpen else { return }
        if let workflowRun = run.workflowRun {
            host?.cancelWorkflowRun(workflowRun)
        } else {
            book.update(id) {
                $0.status = .cancelled
                $0.endedAt = now()
            }
        }
    }

    // MARK: - Events from Native

    /// A task the user started finished a turn in `project`.
    public func noteTaskFinished(project: URL, title: String) {
        ingest([AutomationOccurrence(kind: .taskFinished, key: UUID().uuidString, project: project, subject: title, occurredAt: now())])
    }

    public func noteBranchPushed(project: URL, branch: String) {
        ingest([AutomationOccurrence(kind: .branchPushed, key: UUID().uuidString, project: project, subject: branch, occurredAt: now())])
    }

    public func ingest(_ occurrences: [AutomationOccurrence]) {
        for occurrence in occurrences {
            for automation in book.automations where automation.matches(occurrence) {
                let key = "\(automation.id):\(occurrence.key)"
                guard !book.handledEvents.contains(key) else { continue }
                book.noteHandled(key)
                fire(automation.id, reason: .event(occurrence))
            }
        }
    }

    /// Call whenever a workflow run changes; runs that belong to an automation update its history.
    public func workflowRunChanged(_ run: WorkflowRun) {
        guard let entry = book.runs.first(where: { $0.workflowRun == run.id }) else { return }
        let stopped = run.steps.first { $0.status.isStopped }.map { "\($0.step.title): \($0.status.reason ?? $0.status.label)" }
        let status = AutomationRunStatus(phase: run.phase, reason: stopped)
        guard status != entry.status else { return }
        book.update(entry.id) { entry in
            entry.status = status
            guard !status.isOpen else { return }
            entry.endedAt = now()
            let result = run.steps.last { $0.status == .succeeded }?.output
            entry.summary = status == .succeeded ? result.map(Self.firstLine) : stopped ?? result.map(Self.firstLine)
        }
    }

    // MARK: - Scheduling

    /// Checks schedules and events once. The loop calls it; tests call it directly.
    public func tick() async {
        guard isEnabled else { return }
        let date = now()
        for (id, reason) in AutomationPlanner.due(book.automations, lastChecked: book.lastChecked, now: date) {
            book.lastChecked[id] = date
            fire(id, reason: reason)
        }
        guard needsPolling, lastPoll.map({ date.timeIntervalSince($0) >= Self.pollInterval - 1 }) ?? true else { return }
        lastPoll = date
        guard let host else { return }
        do {
            let snapshots = try await host.pullRequestSnapshots()
            eventSourceProblem = nil
            ingest(AutomationEventDetector.occurrences(from: book.pullRequests, to: snapshots, at: date))
            book.pullRequests = snapshots
        } catch {
            eventSourceProblem = error.localizedDescription
        }
    }

    /// Whether any automation waits on a pull request event, so GitHub has to be watched.
    public var needsPolling: Bool {
        let gitHubEvents: Set<AutomationEventKind> = [.pullRequestOpened, .pullRequestUpdated, .reviewRequested, .checksFailed]
        return book.automations.contains { !$0.isPaused && !$0.eventKinds.isDisjoint(with: gitHubEvents) }
    }

    private func reschedule() {
        loop?.cancel()
        guard host != nil, isEnabled else { return }
        loop = Task { [weak self] in
            while !Task.isCancelled, let self {
                await self.tick()
                guard let delay = self.sleepInterval() else { return }
                try? await Task.sleep(for: .seconds(delay))
            }
        }
    }

    /// Seconds until the next thing to do; nil when nothing is scheduled or watched (a change
    /// reschedules).
    private func sleepInterval() -> TimeInterval? {
        let date = now()
        var delays: [TimeInterval] = []
        if let wake = AutomationPlanner.nextWake(book.automations, lastChecked: book.lastChecked, now: date) {
            delays.append(wake.timeIntervalSince(date))
        }
        if needsPolling {
            delays.append(Self.pollInterval)
        }
        return delays.min().map { max($0, 1) }
    }

    // MARK: - Runs

    private func fire(_ id: Automation.ID, reason: AutomationRunReason) {
        guard let automation = book.automation(id) else { return }
        guard book.openRun(of: id) == nil else {
            // Runs never pile up: the next trigger after this one starts a run if this one is done.
            book.record(AutomationRun(automation: id, reason: reason, startedAt: now(), status: .skipped("The previous run was still going.")))
            return
        }
        let run = AutomationRun(automation: id, reason: reason, startedAt: now())
        book.record(run)
        Task { await start(run.id, of: automation, reason: reason) }
    }

    private func start(_ runID: AutomationRun.ID, of automation: Automation, reason: AutomationRunReason) async {
        guard let host else { return }
        do {
            guard let (definition, input) = automation.action.workflow(named: automation.name, library: host.workflowLibrary, context: reason.context) else {
                throw AutomationError.workflowMissing
            }
            let workspace = try await host.prepareWorkspace(for: automation, title: automation.name)
            // The user may have stopped it while the worktree was being made.
            guard book.runs.first(where: { $0.id == runID })?.status == .preparing else { return }
            let defaultSteps = definition.steps.filter { $0.kind == .agent && $0.agent == nil && $0.continues == nil }
            let overrides = automation.agent.map { agent in Dictionary(uniqueKeysWithValues: defaultSteps.map { ($0.id, agent) }) } ?? [:]
            let workflowRun = host.startWorkflow(definition, input: input, cwd: workspace, overrides: overrides)
            book.update(runID) {
                $0.workspace = workspace
                $0.workflowRun = workflowRun
                $0.status = .running
            }
            if let run = host.workflowRun(workflowRun) {
                workflowRunChanged(run)
            }
        } catch {
            book.update(runID) {
                $0.status = .failed(error.localizedDescription)
                $0.endedAt = now()
                $0.summary = error.localizedDescription
            }
        }
    }

    /// After a restart, runs that were open pick up their workflow run's state (interrupted steps
    /// show as such), and runs that hadn't started yet say so.
    private func reconcileOpenRuns() {
        guard let host else { return }
        for run in book.runs where run.status.isOpen {
            if let workflowRun = run.workflowRun.flatMap(host.workflowRun) {
                workflowRunChanged(workflowRun)
            } else if run.workflowRun == nil {
                book.update(run.id) {
                    $0.status = .failed(AutomationError.interruptedWhileStarting.localizedDescription)
                    $0.endedAt = now()
                }
            }
        }
    }

    private static func firstLine(_ text: String) -> String {
        text.split(whereSeparator: \.isNewline).first.map(String.init) ?? text
    }
}
