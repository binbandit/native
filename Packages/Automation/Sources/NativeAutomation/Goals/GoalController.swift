import Foundation
import Observation

/// A session's goal, live: the views read it and call its actions, and the session's turns are
/// reported to it. All decisions are `GoalLoop`'s; this only adds the clock, the session and storage.
@MainActor
@Observable
public final class GoalController {
    public private(set) var loop: GoalLoop?
    /// Set to ask the session's view to open the goal editor; the view clears it.
    public var isEditorRequested = false

    /// The session it drives; adapters hold their session weakly, so this can be strong.
    @ObservationIgnored public var host: (any GoalHost)?
    @ObservationIgnored private let strategy: GoalLoop.Strategy
    @ObservationIgnored private let storage: (store: GoalStore, key: String)?
    @ObservationIgnored private let now: () -> Date

    /// `storageKey` identifies the session across launches (its agent and session id); nil keeps the
    /// goal in memory only.
    public init(strategy: GoalLoop.Strategy = .native, store: GoalStore? = .standard, storageKey: String?, now: @escaping () -> Date = Date.init) {
        self.strategy = strategy
        self.now = now
        if let store, let storageKey {
            storage = (store, storageKey)
            loop = store.loop(for: storageKey)?.restored()
        } else {
            storage = nil
        }
    }

    public var goal: Goal? {
        loop?.goal
    }

    // MARK: - User actions

    public func set(objective: String, budget: GoalBudget) async {
        let objective = objective.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !objective.isEmpty else { return }
        if let clear = loop?.clearPrompt, host?.canSendGoalPrompt == true {
            await host?.sendGoalPrompt(clear)
        }
        change { $0 = GoalLoop(objective: objective, budget: budget, strategy: strategy, at: now(), sessionCost: host?.goalSessionCost) }
        await sendIfIdle()
    }

    /// Edits the goal in place; its progress so far carries over.
    public func update(objective: String, budget: GoalBudget) async {
        let objective = objective.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !objective.isEmpty else { return }
        let date = now()
        change { $0?.update(objective: objective, budget: budget, at: date) }
        await sendIfIdle()
    }

    public func pause() {
        let date = now()
        change { $0?.pause(at: date) }
    }

    public func resume() async {
        let date = now()
        change { $0?.resume(at: date) }
        await sendIfIdle()
    }

    /// Grants the budget again and resumes: the way out of a spent budget.
    public func extendAndResume() async {
        let date = now()
        change {
            $0?.extendBudget(at: date)
            $0?.resume(at: date)
        }
        await sendIfIdle()
    }

    public func clear() async {
        if let clear = loop?.clearPrompt, host?.canSendGoalPrompt == true {
            await host?.sendGoalPrompt(clear)
        }
        change { $0 = nil }
    }

    /// Carries out a `/goal` command from the composer.
    public func perform(_ command: GoalCommand) async {
        switch command {
        case .set(let objective):
            if loop == nil {
                await set(objective: objective, budget: .unlimited)
            } else {
                await update(objective: objective, budget: loop?.goal.budget ?? .unlimited)
            }
        case .edit: isEditorRequested = true
        case .pause: pause()
        case .resume: await resume()
        case .clear: await clear()
        }
    }

    // MARK: - Session hooks

    /// Call as every prompt goes out, with who sent it.
    public func turnWillStart(_ origin: GoalLoop.Origin) {
        let date = now()
        change { $0?.turnWillStart(origin, at: date) }
    }

    /// Call when a turn ends, however it ended. Sends the goal's next prompt when it has one, unless
    /// the user queued messages: those go first, and the goal decides again after them.
    public func turnDidEnd(_ outcome: TurnOutcome) async {
        let date = now()
        let cost = host?.goalSessionCost
        let reply = host?.goalLatestReply
        var next: String?
        change { next = $0?.turnDidEnd(outcome, reply: reply, sessionCost: cost, at: date) }
        guard let next, let host, host.canSendGoalPrompt else { return }
        await host.sendGoalPrompt(next)
    }

    // MARK: - Internals

    private func sendIfIdle() async {
        guard let host, host.canSendGoalPrompt, let prompt = loop?.nextPrompt(at: now()) else { return }
        await host.sendGoalPrompt(prompt)
    }

    private func change(_ body: (inout GoalLoop?) -> Void) {
        body(&loop)
        if let storage {
            storage.store.save(loop, for: storage.key)
        }
    }
}
