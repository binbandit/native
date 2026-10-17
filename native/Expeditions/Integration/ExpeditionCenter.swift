#if EXPEDITIONS_WIP
import ACP
import Foundation
import NativeAutomation
import NativeExpeditions
import Observation

/// Expeditions for the whole app: the views find them here, `ExpeditionsPlugin` feeds it every
/// session's turns, and the composition root connects it to the features it composes (sessions,
/// Git worktrees, GitHub pull requests, Usage limits).
@MainActor
@Observable
final class ExpeditionCenter {
    let runner = ExpeditionRunner(store: .standard, documents: .standard)
    /// Set to ask the window to show the New Expedition sheet; the view clears it.
    var isNewExpeditionRequested = false
    /// Set to ask the window to show the Expeditions page, opened on `requestedExpedition` if set.
    var isPageRequested = false
    var requestedExpedition: Expedition.ID?

    @ObservationIgnored private(set) var host: AppExpeditionHost?
    /// Whether a project can have a worktree, has uncommitted changes, and whether `gh` is ready,
    /// for the readiness checks; from the Git and GitHub features.
    @ObservationIgnored var probe: ((URL) async -> ExpeditionProjectProbe)?
    /// Describes a provider limit an error reports, the Usage feature's way; nil when it isn't one.
    @ObservationIgnored var describeLimit: ((any Error) -> String?)?

    func connect(
        to model: AppModel,
        prepareBase: @escaping (_ project: URL, _ title: String, _ worktree: Bool) async throws -> URL,
        openPullRequest: @escaping (WorkflowPullRequestDraft) async throws -> WorkflowPullRequestResult,
        limitStatus: @escaping (AgentDefinition.ID) -> LimitStatus?
    ) {
        let host = AppExpeditionHost(model: model)
        host.prepareBaseHandler = prepareBase
        host.openPullRequestHandler = openPullRequest
        host.limitStatusHandler = limitStatus
        host.onOpenNotification = { [weak self] id in self?.show(id) }
        self.host = host
        runner.host = host
    }

    /// Opens the Expeditions page, on `expedition` if given.
    func show(_ expedition: Expedition.ID? = nil) {
        requestedExpedition = expedition
        isPageRequested = true
    }

    /// Expeditions waiting on the user, for the sidebar's count.
    var waitingCount: Int {
        runner.expeditions.count { $0.phase.needsUser }
    }

    func handle(_ event: SessionEvent) async {
        switch event {
        case .turnEnded(let context, let stopReason):
            runner.turnEnded(task: host?.task(forClient: context.clientID) ?? context.clientID, outcome: TurnOutcome(stopReason: stopReason, error: nil))
        case .turnFailed(let context, _, let error, _):
            let outcome = describeLimit?(error).map(TurnOutcome.limited) ?? .failure(error.localizedDescription)
            runner.turnEnded(task: host?.task(forClient: context.clientID) ?? context.clientID, outcome: outcome)
        case .sessionStarted, .promptSent, .permissionRequested, .usageUpdated:
            break
        }
    }
}

/// What the readiness checks need to know about a project.
struct ExpeditionProjectProbe {
    var isRepository: Bool
    var hasUncommittedChanges: Bool
    var gitHubReady: Bool?
}
#endif
