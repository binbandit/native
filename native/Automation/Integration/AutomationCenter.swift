import ACP
import Foundation
import NativeAutomation
import Observation

/// Goals and workflows for the whole app: the views find a session's goal and the workflow runs
/// here, and `AutomationPlugin` feeds it every session's turns.
@MainActor
@Observable
final class AutomationCenter {
    let workflows = WorkflowRunner(store: .standard)
    private(set) var library = WorkflowLibrary()
    /// Set to ask the window to show the workflow picker; the view clears it.
    var isWorkflowPickerRequested = false
    /// The workflow the picker opens with, when it was asked for from a library card.
    var pickerSelection: String?

    /// The app, once it's wired up. Until then goals and workflows stay idle.
    @ObservationIgnored var host: AppAutomationHost? {
        didSet { workflows.host = host }
    }
    /// Describes a provider limit an error reports, with its reset time (the Usage feature's
    /// wording); nil when the error isn't a limit. Without it, limits are recognized by their
    /// message and shown as the provider worded them.
    @ObservationIgnored var describeLimit: ((any Error) -> String?)?

    // Goals are created on demand and observed one by one, so the dictionary itself isn't.
    @ObservationIgnored private var goals: [String: GoalController] = [:]
    @ObservationIgnored private let goalStore: GoalStore

    init(goalStore: GoalStore = .standard) {
        self.goalStore = goalStore
    }

    /// Wires the center to the app: workflow steps run as the app's task sessions, pull request steps
    /// go through `openPullRequest` (the Git and GitHub features), and provider limits read the way
    /// the rest of Native words them.
    func connect(to model: AppModel, openPullRequest: @escaping (WorkflowPullRequestDraft) async throws -> WorkflowPullRequestResult) {
        let host = AppAutomationHost(model: model)
        host.openPullRequestHandler = openPullRequest
        self.host = host
        describeLimit = { UsageLimitHit(error: $0)?.message }
    }

    /// Opens the workflow picker, with `workflow` chosen if given.
    func requestPicker(selecting workflow: String? = nil) {
        pickerSelection = workflow
        isWorkflowPickerRequested = true
    }

    /// The goal controller for a session the user can prompt; nil for subagents and task sessions,
    /// which take their work from elsewhere.
    func goal(for session: SessionModel) -> GoalController? {
        guard session.origin == .user else { return nil }
        let key = Self.goalKey(agent: session.agent.id, session: session.id)
        if let controller = goals[key] {
            return controller
        }
        let controller = GoalController(store: goalStore, storageKey: key)
        controller.host = SessionGoalHost(session)
        goals[key] = controller
        return controller
    }

    /// Plugins' workflows, by plugin id, after the built-ins.
    func reloadLibrary(contributions: [(plugin: String, workflows: [WorkflowDefinition])]) {
        library = WorkflowLibrary(contributions: contributions)
    }

    /// Picks up the workflows enabled plugins contribute. Call when plugins change.
    func reloadLibrary(from plugins: PluginRegistry) {
        reloadLibrary(contributions: plugins.enabledPlugins.compactMap { plugin in
            plugin.manifest.workflows.isEmpty ? nil : (plugin: plugin.manifest.id, workflows: plugin.manifest.workflows)
        })
    }

    // MARK: - Session events

    func handle(_ event: SessionEvent) async {
        switch event {
        case .promptSent(let context, let text):
            existingGoal(for: context)?.turnWillStart(GoalPrompt(parsing: text) == nil ? .user : .goal)
        case .turnEnded(let context, let stopReason):
            await turnEnded(context, outcome: TurnOutcome(stopReason: stopReason, error: nil))
        case .turnFailed(let context, _, let error, _):
            let outcome = describeLimit?(error).map(TurnOutcome.limited) ?? .failure(error.localizedDescription)
            await turnEnded(context, outcome: outcome)
        case .sessionStarted, .permissionRequested, .usageUpdated:
            break
        }
    }

    private func turnEnded(_ context: SessionContext, outcome: TurnOutcome) async {
        workflows.turnEnded(task: context.clientID, outcome: outcome)
        await existingGoal(for: context)?.turnDidEnd(outcome)
    }

    /// The goal of the session an event is about, if it has one: in memory, or saved from an
    /// earlier launch.
    private func existingGoal(for context: SessionContext) -> GoalController? {
        guard context.parentID == nil, let sessionID = context.sessionID else { return nil }
        let key = Self.goalKey(agent: context.agent, session: sessionID)
        if let controller = goals[key] {
            return controller.goal == nil ? nil : controller
        }
        guard goalStore.loop(for: key) != nil, let session = host?.session(for: context.clientID) else { return nil }
        return goal(for: session)
    }

    /// Goals outlive Native's own session ids, which are new each launch, so they're kept by the
    /// agent's.
    private static func goalKey(agent: AgentDefinition.ID, session: SessionID) -> String {
        "\(agent.rawValue)/\(session)"
    }
}
