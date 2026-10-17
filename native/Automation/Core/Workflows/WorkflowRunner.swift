import Foundation
import Observation

/// The app's workflow runs, live. Starts runs, forwards the user's actions and the tasks' turn ends
/// to each `WorkflowRun`, and carries out the effects it asks for through the host.
@MainActor
@Observable
final class WorkflowRunner {
    private(set) var runs: [WorkflowRun] = [] {
        didSet { store?.save(runs) }
    }

    @ObservationIgnored var host: (any WorkflowHost)?
    /// Called after every change to a run, for whoever follows runs from outside (automations).
    @ObservationIgnored var onRunChange: ((WorkflowRun) -> Void)?
    @ObservationIgnored private let store: WorkflowRunStore?
    @ObservationIgnored private let now: () -> Date

    /// With a store, runs from earlier launches come back (interrupted where they were working) and
    /// every change is saved.
    init(store: WorkflowRunStore? = nil, now: @escaping () -> Date = Date.init) {
        self.store = store
        self.now = now
        runs = store?.load() ?? []
    }

    func run(_ id: WorkflowRun.ID) -> WorkflowRun? {
        runs.first { $0.id == id }
    }

    /// The agents each step would get, for the picker to show before anything runs.
    func plan(for definition: WorkflowDefinition, overrides: [String: WorkflowAgent.ID] = [:]) -> [String: WorkflowAssignment] {
        WorkflowAssignment.resolve(definition, agents: host?.workflowAgents ?? [], defaultAgent: host?.defaultWorkflowAgent, overrides: overrides)
    }

    /// Starts `definition` in `cwd` and returns the new run's id.
    @discardableResult
    func start(_ definition: WorkflowDefinition, input: String, cwd: URL, overrides: [String: WorkflowAgent.ID] = [:]) -> WorkflowRun.ID {
        let run = WorkflowRun(definition: definition, input: input, cwd: cwd, assignments: plan(for: definition, overrides: overrides), at: now())
        runs.insert(run, at: 0)
        send(.start, to: run.id)
        return run.id
    }

    func send(_ event: WorkflowEvent, to id: WorkflowRun.ID) {
        guard let index = runs.firstIndex(where: { $0.id == id }) else { return }
        let effects = runs[index].handle(event, at: now())
        onRunChange?(runs[index])
        perform(effects, for: id)
    }

    /// Forgets a run that's over. Its step sessions stay with their agents.
    func remove(_ id: WorkflowRun.ID) {
        runs.removeAll { $0.id == id && [.succeeded, .cancelled, .halted].contains($0.phase) }
    }

    /// Call when any session's turn ends; runs pick out their own tasks.
    func turnEnded(task: UUID, outcome: TurnOutcome) {
        for run in runs {
            guard let step = run.step(forTask: task), run.stepRun(step)?.status == .running else { continue }
            let report = host?.stepTaskReport(task)
            send(.turnEnded(step: step, outcome: outcome, reply: report?.reply, cost: report?.cost), to: run.id)
        }
    }

    func report(for step: WorkflowStepRun) -> WorkflowTaskReport? {
        step.task.flatMap { host?.stepTaskReport($0) }
    }

    // MARK: - Effects

    private func perform(_ effects: [WorkflowEffect], for run: WorkflowRun.ID) {
        for effect in effects {
            Task { await perform(effect, for: run) }
        }
    }

    private func perform(_ effect: WorkflowEffect, for run: WorkflowRun.ID) async {
        guard let host else {
            if case .createTask(let step, _, _) = effect {
                send(.taskFailed(step: step, message: "Native isn't ready to run workflow steps yet."), to: run)
            }
            return
        }
        switch effect {
        case .createTask(let step, let agent, let title):
            let cwd = self.run(run)?.cwd ?? URL(filePath: "/")
            do {
                let task = try await host.createStepTask(agent: agent.id, title: title, cwd: cwd)
                send(.taskCreated(step: step, task: task), to: run)
            } catch {
                send(.taskFailed(step: step, message: "Couldn't start \(agent.name): \(error.localizedDescription)"), to: run)
            }
        case .prompt(let step, let task, let text):
            do {
                try await host.sendToStepTask(task, text: text)
            } catch {
                send(.taskFailed(step: step, message: "Couldn't send the step's prompt: \(error.localizedDescription)"), to: run)
            }
        case .cancelTask(let task):
            await host.cancelStepTask(task)
        case .openPullRequest(let step, let draft):
            do {
                let result = try await host.openPullRequest(draft)
                send(.pullRequestOpened(step: step, result), to: run)
            } catch {
                send(.pullRequestFailed(step: step, message: error.localizedDescription), to: run)
            }
        case .runScript(let step, let source, let input, let cwd):
            do {
                send(.scriptFinished(step: step, output: try await host.runScript(source, input: input, cwd: cwd)), to: run)
            } catch {
                send(.scriptFailed(step: step, message: error.localizedDescription), to: run)
            }
        }
    }
}
