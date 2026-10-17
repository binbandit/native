import Foundation
import NativeAutomation
import Observation
import os

/// The app's expeditions, live. Starts them, forwards the user's actions and the crew's turn ends
/// to each `Expedition`, carries out the effects it asks for through the host, keeps the artifact
/// files current, resumes seats when a provider limit resets, and notifies about what needs the
/// user. Its whole API is events in and state out, so a client of a host can mirror it.
@MainActor
@Observable
public final class ExpeditionRunner {
    public private(set) var expeditions: [Expedition] = [] {
        didSet { store?.save(expeditions) }
    }

    @ObservationIgnored public var host: (any ExpeditionHost)? {
        didSet { expeditions.forEach(scheduleLimitWakeups) }
    }
    @ObservationIgnored public let documents: ExpeditionDocuments?
    @ObservationIgnored private let store: ExpeditionStore?
    @ObservationIgnored private let now: () -> Date
    @ObservationIgnored private var wakeups: [CrewWakeup: Task<Void, Never>] = [:]
    @ObservationIgnored private let logger = Logger(subsystem: "Native", category: "Expeditions")

    private struct CrewWakeup: Hashable {
        let expedition: Expedition.ID
        let slot: CrewSlot
    }

    /// With a store, expeditions from earlier launches come back (interrupted where they were
    /// working) and every change is saved.
    public init(
        store: ExpeditionStore? = nil, documents: ExpeditionDocuments? = nil, now: @escaping () -> Date = Date.init
    ) {
        self.store = store
        self.documents = documents
        self.now = now
        expeditions = store?.load() ?? []
    }

    public func expedition(_ id: Expedition.ID) -> Expedition? {
        expeditions.first { $0.id == id }
    }

    /// Sets out: makes the base and starts the lead planning. Returns the new expedition's id.
    @discardableResult
    public func start(
        objective: String, project: URL, usesWorktree: Bool, crew: Crew, budget: ExpeditionBudget = .unlimited,
        settings: ExpeditionSettings = ExpeditionSettings()
    ) -> Expedition.ID {
        let expedition = Expedition(
            objective: objective, project: project, usesWorktree: usesWorktree, crew: crew, budget: budget,
            settings: settings, at: now())
        expeditions.insert(expedition, at: 0)
        send(.start, to: expedition.id)
        return expedition.id
    }

    public func send(_ event: ExpeditionEvent, to id: Expedition.ID) {
        guard let index = expeditions.firstIndex(where: { $0.id == id }) else { return }
        let before = expeditions[index]
        let effects = expeditions[index].handle(event, at: now())
        let after = expeditions[index]
        announce(before: before, after: after)
        scheduleLimitWakeups(after)
        perform(effects, for: id)
        for path in documents?.write(after) ?? [] {
            send(.documentRestored(path), to: id)
        }
    }

    /// Forgets an expedition that's over. Its sessions stay with their agents and its worktree
    /// with the Git feature.
    public func remove(_ id: Expedition.ID) {
        expeditions.removeAll { $0.id == id && $0.phase.isOver }
    }

    /// Call when any session's turn ends; expeditions pick out their own crew.
    public func turnEnded(task: UUID, outcome: TurnOutcome) {
        for expedition in expeditions {
            guard let slot = expedition.slot(forTask: task) else { continue }
            let report = host?.crewTaskReport(task)
            send(.turnEnded(slot, outcome: outcome, reply: report?.reply, cost: report?.cost), to: expedition.id)
        }
    }

    public func report(for task: UUID?) -> WorkflowTaskReport? {
        task.flatMap { host?.crewTaskReport($0) }
    }

    // MARK: - Effects

    private func perform(_ effects: [ExpeditionEffect], for id: Expedition.ID) {
        for effect in effects {
            Task { await perform(effect, for: id) }
        }
    }

    private func perform(_ effect: ExpeditionEffect, for id: Expedition.ID) async {
        guard let host else {
            switch effect {
            case .prepareBase: send(.baseFailed("Native isn't ready to run expeditions yet."), to: id)
            case .createTask(let slot, _, _, _):
                send(.taskFailed(slot, message: "Native isn't ready to run expeditions yet."), to: id)
            default: break
            }
            return
        }
        switch effect {
        case .prepareBase(let project, let title, let worktree):
            do {
                send(.baseReady(try await host.prepareBase(project: project, title: title, worktree: worktree)), to: id)
            } catch {
                send(.baseFailed(error.localizedDescription), to: id)
            }
        case .createTask(let slot, let agent, let title, let cwd):
            do {
                let task = try await host.createCrewTask(agent: agent.id, title: title, cwd: cwd)
                send(.taskCreated(slot, task: task), to: id)
            } catch {
                send(.taskFailed(slot, message: "Couldn't start \(agent.name): \(error.localizedDescription)"), to: id)
            }
        case .prompt(let slot, let task, let text):
            do {
                try await host.sendToCrewTask(task, text: text)
            } catch {
                send(.taskFailed(slot, message: "Couldn't send the prompt: \(error.localizedDescription)"), to: id)
            }
        case .message(_, let task, let text):
            do {
                try await host.messageCrewTask(task, text: text)
            } catch {
                logger.error("Couldn't deliver a message to a crew member: \(error)")
            }
        case .cancelTask(let task):
            await host.cancelCrewTask(task)
        case .openPullRequest(let draft):
            do {
                send(.pullRequestOpened(try await host.openPullRequest(draft)), to: id)
            } catch {
                send(.pullRequestFailed(error.localizedDescription), to: id)
            }
        }
    }

    // MARK: - Limits

    /// Resumes each seat a provider limit stopped once the Usage feature says the limit resets.
    private func scheduleLimitWakeups(_ expedition: Expedition) {
        for slot in expedition.allSlots {
            let key = CrewWakeup(expedition: expedition.id, slot: slot)
            guard case .limited = expedition.status(of: slot),
                let reset = host?.limitReset(agent: expedition.agent(of: slot).id)
            else {
                wakeups.removeValue(forKey: key)?.cancel()
                continue
            }
            guard wakeups[key] == nil else { continue }
            let delay = max(0, reset.timeIntervalSince(now())) + 30
            wakeups[key] = Task { [weak self] in
                try? await Task.sleep(for: .seconds(delay))
                guard !Task.isCancelled else { return }
                self?.wakeups[key] = nil
                self?.send(.limitReset(slot), to: expedition.id)
            }
        }
    }

    // MARK: - Notifications

    private func announce(before: Expedition, after: Expedition) {
        let known = Set(before.attention.map(\.id))
        for item in after.attention where !known.contains(item.id) {
            host?.notify(
                ExpeditionNotice(
                    expedition: after.id, title: after.headline(for: item), body: after.detail(for: item) ?? after.title
                ))
        }
        if before.phase != .complete, after.phase == .complete {
            let body = after.pullRequest.map { "Pull request: \($0.url.absoluteString)" } ?? "The debrief is ready."
            host?.notify(
                ExpeditionNotice(expedition: after.id, title: "Expedition complete: \(after.title)", body: body))
        }
    }
}
