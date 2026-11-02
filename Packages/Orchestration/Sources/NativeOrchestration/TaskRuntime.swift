import Foundation

/// What the orchestration engine needs from whatever runs the sessions: Native's host, or the app
/// when agents run inside it. Sessions are named by `TaskSessionRef`; a caller is known by Native's
/// id for it (`OrchestrationCaller.clientID`), which its token names.
public protocol TaskRuntime: Sendable {
    /// Whether tasks can run yet. Until then the tools say so and to try again shortly.
    var isReady: Bool { get async }
    var supportsDurableTasks: Bool { get async }

    /// Agents that can run a task right now.
    func taskAgents() async -> [TaskAgent]

    /// The session with this id, if it's one the runtime has open.
    func caller(of clientID: UUID) async -> OrchestrationCaller?

    /// The lasting name of the session with this id, once the agent has given it an id.
    func session(of clientID: UUID) async -> TaskSessionRef?

    /// Nil for ordinary tasks; an empty scope still restricts a coordinator.
    func coordinatorScope(of clientID: UUID) async -> CoordinatorScope?
    func openCoordinatedTask(_ session: TaskSessionRef) async throws
    func recentTranscript(of session: TaskSessionRef) async -> String?

    /// Every task sessions handed each other, in the order they started.
    func tasks() async -> [OrchestrationTask]

    /// Validates exact launch options and bounded inherited permissions before the first prompt.
    /// Starts a session on the requested agent and checkout (parent's directory by default), shows it as a
    /// task of the parent, remembers it, and sends it the request's prompt. Returns once the prompt
    /// is on its way: from then on `snapshot` must report the turn (running or later), never the
    /// idle state before it, or a wait could end before the task begins. The new session gets
    /// Native's tools like any other, which is how tasks can start and message tasks too.
    func startTask(_ request: TaskRequest) async throws -> OrchestrationTask
    func startTaskReceipt(_ request: TaskRequest) async throws -> TaskStartReceipt
    func originalResult(of session: TaskSessionRef) async -> TaskSnapshot?
    func acknowledgeResult(of session: TaskSessionRef, by clientID: UUID) async throws

    /// Makes sure a task that isn't open (after a restart, or closed meanwhile) is open again and
    /// shown in its parent's transcript. Does nothing for an open task.
    func openTask(_ task: OrchestrationTask) async throws

    /// An open session's state as it is now, or nil if it isn't open.
    func snapshot(of session: TaskSessionRef) async -> TaskSnapshot?

    /// Returns once the session's turn isn't running (it ended or needs approval), after `timeout`,
    /// or when the calling task is cancelled.
    func settle(_ session: TaskSessionRef, timeout: Duration) async

    /// Delivers a message from one open session to another without waiting for a reply. Records it
    /// in both transcripts as a session message (outgoing in the sender's, incoming in the
    /// recipient's) showing `text`, and hands the recipient's agent `prompt`: steered into its
    /// running turn if the agent supports that, else queued as its next prompt; or, when it's idle,
    /// sent as a prompt that has started (as with `startTask`) by the time this returns.
    func deliver(_ message: TaskMessage) async throws -> TaskMessage.Delivery

    /// Cancels the task's current turn, answering any permission requests it has open as cancelled.
    func cancelTask(_ session: TaskSessionRef) async

    /// Names of Native's skills switched off for the session with this id (Settings ▸ Skills),
    /// which the skill tools leave out for it.
    func disabledSkills(of clientID: UUID) async -> Set<String>
}

public extension TaskRuntime {
    var supportsDurableTasks: Bool { false }
    func startTaskReceipt(_ request: TaskRequest) async throws -> TaskStartReceipt {
        guard request.creationKey == nil, request.notifyOnCompletion != true else {
            throw TaskLaunchValidation.Refusal(
                "Retry-safe creation and completion delivery require Native's host tools.")
        }
        let task = try await startTask(request)
        return TaskStartReceipt(task: task, snapshot: await snapshot(of: task.session))
    }
    func originalResult(of session: TaskSessionRef) async -> TaskSnapshot? { nil }
    func acknowledgeResult(of session: TaskSessionRef, by clientID: UUID) async throws {}
    func openCoordinatedTask(_ session: TaskSessionRef) async throws {}
    func coordinatorScope(of clientID: UUID) async -> CoordinatorScope? { nil }
    func recentTranscript(of session: TaskSessionRef) async -> String? { nil }
}
