import Foundation

/// What the orchestration tools need from the app: sessions they can start, watch, message and
/// cancel on behalf of an agent. Sessions are named by their `SessionContext.clientID`.
@MainActor
protocol OrchestrationHost: AnyObject, Sendable {
    /// Agents that can run a task right now.
    var taskAgents: [AgentDefinition] { get }

    /// Starts a session on the request's agent in its parent's working directory, shows it as a
    /// subagent of the parent, and sends it the request's prompt. Returns the new session's client
    /// id once the prompt is on its way: from then on `taskSnapshot` must report the turn (running
    /// or later), never the idle state before it, or a wait could end before the task begins. The
    /// new session gets plugins' MCP servers like any other, which is how tasks can start and
    /// message tasks too.
    func startTask(_ request: TaskRequest) async throws -> UUID

    /// Any session's state as it is now, or nil if it's gone. Waits re-read this whenever state it
    /// read changes, so it must be built from observable state only.
    func taskSnapshot(_ session: UUID) -> TaskSnapshot?

    /// Delivers a message from one session to another without waiting for a reply. Records it in
    /// both transcripts as a session message (`SessionUpdate.sessionMessage`, outgoing in the
    /// sender's and incoming in the recipient's, each with its own message id) showing `text`, and
    /// hands the recipient's agent `prompt`: steered into its running turn if the agent supports
    /// that, else queued as its next prompt; or, when it's idle, sent as a prompt that has started
    /// (as with `startTask`) by the time this returns.
    func deliver(_ message: TaskMessage) async throws -> TaskMessage.Delivery

    /// Cancels the task's current turn, answering any permission requests it has open as cancelled.
    func cancelTask(_ task: UUID) async
}
