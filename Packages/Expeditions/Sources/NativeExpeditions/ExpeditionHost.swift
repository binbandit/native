import Foundation
import NativeAutomation

/// What expeditions need from the app. Crew members are sessions, named by
/// `SessionContext.clientID`; the app reports their turns ending through
/// `ExpeditionRunner.turnEnded(task:outcome:)`.
@MainActor
public protocol ExpeditionHost: AnyObject {
    /// Agents that can take a seat right now.
    var expeditionAgents: [WorkflowAgent] { get }

    /// Makes the folder the crew shares: a worktree on a branch of its own, or the project itself.
    func prepareBase(project: URL, title: String, worktree: Bool) async throws -> URL
    /// Creates an idle session on `agent` in `cwd`, out of the sidebar but reachable by its id.
    func createCrewTask(agent: WorkflowAgent.ID, title: String, cwd: URL) async throws -> UUID
    /// Sends `text` as the session's next prompt; returns once the turn is under way.
    func sendToCrewTask(_ task: UUID, text: String) async throws
    /// Hands the user's message to a session that's working: steered in where the agent supports
    /// it, queued otherwise.
    func messageCrewTask(_ task: UUID, text: String) async throws
    func cancelCrewTask(_ task: UUID) async
    /// The session's state now, or nil when it isn't open. Built from observable state, since the
    /// overview reads it.
    func crewTaskReport(_ task: UUID) -> WorkflowTaskReport?
    /// Opens a pull request from the branch checked out in the draft's folder: the GitHub feature.
    func openPullRequest(_ draft: WorkflowPullRequestDraft) async throws -> WorkflowPullRequestResult
    /// When the agent's provider limit resets, as the Usage feature knows it; nil when no limit is
    /// in force or its reset isn't known.
    func limitReset(agent: WorkflowAgent.ID) -> Date?
    /// Tells the user something about an expedition while they're elsewhere.
    func notify(_ notice: ExpeditionNotice)
}

/// A notification about an expedition: what needs the user, or that it's done.
public nonisolated struct ExpeditionNotice: Hashable, Sendable {
    public var expedition: UUID
    public var title: String
    public var body: String

    public init(expedition: UUID, title: String, body: String) {
        self.expedition = expedition
        self.title = title
        self.body = body
    }
}
