import Foundation

/// One run of a workflow, and its state machine. Like `GoalLoop` it never touches an agent: events
/// go in, effects for the host come out (`handle(_:at:)`), so scheduling, gates, goal steps and
/// failure handling are all testable without sessions.
///
/// Scheduling: a step starts once every step it waits for has finished (succeeded or skipped), so
/// steps with the same dependencies run in parallel. A step that stops short (failed, cancelled,
/// limited, blocked) holds back only the steps that wait for it, until the user retries, resumes,
/// answers, accepts or skips it. Nothing is ever retried automatically.
nonisolated struct WorkflowRun: Codable, Hashable, Sendable, Identifiable {
    let id: UUID
    let definition: WorkflowDefinition
    /// What the user typed for the workflow's input.
    let input: String
    let title: String
    /// The project folder every step works in.
    let cwd: URL
    let createdAt: Date
    var steps: [WorkflowStepRun]
    private(set) var isCancelled = false
    private(set) var isPaused = false
    private(set) var endedAt: Date?

    init(
        id: UUID = UUID(), definition: WorkflowDefinition, input: String, cwd: URL,
        assignments: [String: WorkflowAssignment], at now: Date
    ) {
        self.id = id
        self.definition = definition
        self.input = input.trimmingCharacters(in: .whitespacesAndNewlines)
        title = Self.title(for: self.input, definition: definition)
        self.cwd = cwd
        createdAt = now
        steps = definition.steps.map { step in
            WorkflowStepRun(step: step, assignment: assignments[step.id] ?? WorkflowAssignment(agent: nil))
        }
    }

    /// The run's name: the first line of the input, or the workflow's name without one.
    static func title(for input: String, definition: WorkflowDefinition) -> String {
        let line = input.split(whereSeparator: \.isNewline).first.map(String.init)?.trimmingCharacters(in: .whitespaces) ?? ""
        guard !line.isEmpty else { return definition.name }
        return line.count > 72 ? String(line.prefix(71)) + "…" : line
    }

    // MARK: - Queries

    func stepRun(_ id: String) -> WorkflowStepRun? {
        steps.first { $0.id == id }
    }

    /// The step whose turn is running in `task`. Several steps can share a task (`continues`), but
    /// only one at a time uses it.
    func step(forTask task: UUID) -> String? {
        steps.last { $0.task == task && ($0.status.isActive || $0.status.isStopped) }?.id
            ?? steps.last { $0.task == task }?.id
    }

    var phase: WorkflowRunPhase {
        if isCancelled { return .cancelled }
        if steps.allSatisfy(\.status.isFinished) { return .succeeded }
        if isPaused { return .paused }
        if steps.contains(where: { $0.status == .awaitingApproval }) { return .awaitingApproval }
        if steps.contains(where: { if case .blocked = $0.status { true } else { false } }) { return .blocked }
        if steps.contains(where: \.status.isActive) { return .running }
        return steps.contains(where: \.status.isStopped) ? .halted : .running
    }

    var finishedCount: Int {
        steps.count(where: \.status.isFinished)
    }

    var cost: Double? {
        let costs = steps.compactMap(\.cost)
        return costs.isEmpty ? nil : costs.reduce(0, +)
    }

    /// The step waiting on the user the longest; it answers the approval shortcuts.
    var oldestRequest: WorkflowStepRun? {
        steps.filter(\.needsUser).min { ($0.waitingSince ?? .distantFuture) < ($1.waitingSince ?? .distantFuture) }
    }

    /// The values the step's templates are filled with: the finished steps' outputs so far.
    var templateValues: WorkflowTemplate.Values {
        var values = WorkflowTemplate.Values(input: input, title: title, cwd: cwd)
        for run in steps {
            if run.status.isFinished {
                values.outputs[run.id] = run.output ?? ""
            }
            values.agents[run.id] = run.assignment.agent?.name
        }
        return values
    }

    // MARK: - Mutation helpers shared by the event handlers

    func index(of step: String) -> Int? {
        steps.firstIndex { $0.id == step }
    }

    mutating func markCancelled(at now: Date) {
        isCancelled = true
        isPaused = false
        endedAt = now
    }

    /// The run as found on the next launch. Turns that were in flight died with the host, so their
    /// steps are interrupted until the user resumes them; goals inside stop their clocks.
    func restored() -> WorkflowRun {
        var run = self
        for index in run.steps.indices where run.steps[index].status.isActive {
            run.steps[index].status = .interrupted
            run.steps[index].goal = run.steps[index].goal?.restored()
            run.steps[index].waitingSince = run.steps[index].startedAt
        }
        return run
    }

    mutating func setPaused(_ paused: Bool) {
        isPaused = paused && !isCancelled
    }

    mutating func noteEnded(at now: Date) {
        if endedAt == nil, phase == .succeeded {
            endedAt = now
        }
    }
}
