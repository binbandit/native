import Foundation

/// What the orchestration tools need from the app: sessions they can start, reopen, watch, message
/// and cancel on behalf of an agent. Sessions are named by their `SessionKey`, which outlives a
/// launch; a caller is known by its `SessionContext.clientID` until it has one.
@MainActor
protocol OrchestrationHost: AnyObject, Sendable {
    /// Agents that can run a task right now.
    var taskAgents: [AgentDefinition] { get }

    /// The open session with this client id, once the agent has given it an id.
    func sessionKey(of clientID: UUID) -> SessionKey?

    /// Starts a session on the request's agent in its parent's working directory, shows it as a
    /// subagent of the parent, and sends it the request's prompt. Returns once the prompt is on its
    /// way: from then on `taskSnapshot` must report the turn (running or later), never the idle
    /// state before it, or a wait could end before the task begins. The new session gets plugins'
    /// MCP servers like any other, which is how tasks can start and message tasks too.
    func startTask(_ request: TaskRequest) async throws -> SessionKey

    /// Makes sure a task started in an earlier launch is open again, attached to its parent and
    /// shown in the parent's transcript, once the parent has loaded. Does nothing for an open task.
    func openTask(_ task: OrchestrationTask) async throws

    /// An open session's state as it is now, or nil if it isn't open. Waits re-read this whenever
    /// state it read changes, so it must be built from observable state only.
    func taskSnapshot(_ session: SessionKey) -> TaskSnapshot?

    /// Delivers a message from one open session to another without waiting for a reply. Records it
    /// in both transcripts as a session message (`SessionUpdate.sessionMessage`, outgoing in the
    /// sender's and incoming in the recipient's, each with its own message id) showing `text`, and
    /// hands the recipient's agent `prompt`: steered into its running turn if the agent supports
    /// that, else queued as its next prompt; or, when it's idle, sent as a prompt that has started
    /// (as with `startTask`) by the time this returns.
    func deliver(_ message: TaskMessage) async throws -> TaskMessage.Delivery

    /// Cancels the task's current turn, answering any permission requests it has open as cancelled.
    func cancelTask(_ task: SessionKey) async

    /// Names of the skills switched off for the session with this client id (Settings ▸ Skills),
    /// which the skill tools leave out for it.
    func disabledSkills(of clientID: UUID) -> Set<String>
}
