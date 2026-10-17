#if EXPEDITIONS_WIP
import ACP
import Foundation
import NativeAutomation
import NativeExpeditions
import UserNotifications
#if canImport(AppKit)
    import AppKit
#endif

/// The app as expeditions see it, built on `AppModel`'s public API: crew members are detached task
/// sessions (`startTaskSession`), prompted through `submit` like any session. The base, the pull
/// request and limits come from the features the composition root hands in.
final class AppExpeditionHost: ExpeditionHost {
    private weak var model: AppModel?
    var prepareBaseHandler: ((URL, String, Bool) async throws -> URL)?
    var openPullRequestHandler: ((WorkflowPullRequestDraft) async throws -> WorkflowPullRequestResult)?
    var limitStatusHandler: ((AgentDefinition.ID) -> LimitStatus?)?
    /// Called when the user clicks a notification about an expedition.
    var onOpenNotification: ((Expedition.ID) -> Void)?

    private let records: ExpeditionCrewRecords
    /// Sessions reopened this launch: the expedition's task id to the session's new client id.
    private var reopened: [UUID: UUID] = [:]

    init(model: AppModel, records: ExpeditionCrewRecords = .standard) {
        self.model = model
        self.records = records
    }

    /// A crew member's session, if it's open.
    func session(for task: UUID) -> SessionModel? {
        model?.session(clientID: reopened[task] ?? task)
    }

    /// The task a session's events belong to: the expedition's original id for a reopened session.
    func task(forClient clientID: UUID) -> UUID {
        reopened.first { $0.value == clientID }?.key ?? clientID
    }

    /// The member's session, reopening it from the agent when it didn't survive a restart.
    @discardableResult
    func liveSession(for task: UUID) async throws -> SessionModel {
        if let session = session(for: task) {
            return session
        }
        guard let model, let record = records[task] else { throw ExpeditionHostError.sessionClosed }
        let session = try await model.reopenTaskSession(agent: AgentDefinition.ID(rawValue: record.agent), id: record.session, cwd: record.cwd)
        reopened[task] = session.clientID
        return session
    }

    func limitStatus(for agent: String) -> LimitStatus? {
        limitStatusHandler?(AgentDefinition.ID(rawValue: agent))
    }

    // MARK: - ExpeditionHost

    var expeditionAgents: [WorkflowAgent] {
        (model?.agents ?? []).filter(\.isReady).map { runtime in
            WorkflowAgent(id: runtime.agent.id.rawValue, name: runtime.agent.displayName, symbol: runtime.agent.symbolName)
        }
    }

    func prepareBase(project: URL, title: String, worktree: Bool) async throws -> URL {
        guard worktree else { return project }
        guard let prepareBaseHandler else { throw ExpeditionHostError.gitUnavailable }
        return try await prepareBaseHandler(project, title, worktree)
    }

    func createCrewTask(agent: WorkflowAgent.ID, title: String, cwd: URL) async throws -> UUID {
        guard let model else { throw ExpeditionHostError.appUnavailable }
        let session = try await model.startTaskSession(agent: AgentDefinition.ID(rawValue: agent), cwd: cwd)
        model.rename(session.key, to: title)
        records.remember(ExpeditionCrewRecords.Record(agent: agent, session: session.id, cwd: session.cwd), for: session.clientID)
        return session.clientID
    }

    func sendToCrewTask(_ task: UUID, text: String) async throws {
        _ = try await liveSession(for: task).submit(text, .queue)
    }

    func messageCrewTask(_ task: UUID, text: String) async throws {
        _ = try await liveSession(for: task).submit(text, .steer)
    }

    func cancelCrewTask(_ task: UUID) async {
        await session(for: task)?.cancel()
    }

    func crewTaskReport(_ task: UUID) -> WorkflowTaskReport? {
        guard let session = session(for: task) else { return nil }
        return WorkflowTaskReport(reply: session.state.latestReply, cost: session.state.usage?.cost?.amount, needsApproval: session.needsApproval)
    }

    func openPullRequest(_ draft: WorkflowPullRequestDraft) async throws -> WorkflowPullRequestResult {
        guard let openPullRequestHandler else { throw ExpeditionHostError.pullRequestsUnavailable }
        return try await openPullRequestHandler(draft)
    }

    func limitReset(agent: WorkflowAgent.ID) -> Date? {
        guard let status = limitStatus(for: agent), status.level == .reached else { return nil }
        return status.resetsAt
    }

    func notify(_ notice: ExpeditionNotice) {
        #if canImport(AppKit)
            guard !NSApplication.shared.isActive else { return }
        #endif
        Task {
            let center = UNUserNotificationCenter.current()
            guard (try? await center.requestAuthorization(options: [.alert, .sound])) == true else { return }
            let content = UNMutableNotificationContent()
            content.title = notice.title
            content.body = notice.body
            content.userInfo = ["expedition": notice.expedition.uuidString]
            try? await center.add(UNNotificationRequest(identifier: "expedition-\(UUID().uuidString)", content: content, trigger: nil))
        }
    }
}

enum ExpeditionHostError: LocalizedError {
    case appUnavailable
    case sessionClosed
    case gitUnavailable
    case pullRequestsUnavailable

    var errorDescription: String? {
        switch self {
        case .appUnavailable: "Native isn't ready to run expeditions yet."
        case .sessionClosed: "The crew member's session is gone, and Native has no record of it to reopen. Retry starts a fresh one."
        case .gitUnavailable: "Native couldn't reach the Git feature to make the crew's worktree. Run in the project folder instead."
        case .pullRequestsUnavailable: "Native couldn't reach the GitHub feature to open the pull request. Copy the debrief and open it by hand."
        }
    }
}
#endif
