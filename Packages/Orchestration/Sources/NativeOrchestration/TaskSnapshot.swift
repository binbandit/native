import ACP
import Foundation

/// A session at one moment, as another session sees it.
public struct TaskSnapshot: Hashable, Sendable {
    public enum Status: String, Hashable, Sendable {
        case running
        /// A turn is in progress but blocked on the user answering a permission request.
        case needsApproval = "needs_approval"
        /// The latest turn ended, normally or stopped early by a limit or a refusal.
        case idle
        /// The latest turn errored, or the agent's process is gone.
        case failed
        case cancelled
    }

    /// Where a session is, in the terms every runtime shares.
    public enum Phase: Hashable, Sendable {
        /// Replaying its history, or coming back from an interruption.
        case loading
        /// A turn runs, or is about to (a retry is scheduled).
        case running
        case idle
        /// Its agent can't run it.
        case disconnected
    }

    public var status: Status
    /// What the agent said to close its latest turn, so far; `SessionState.latestReply`.
    public var reply: String?
    /// For needs_approval, what it's asking to do (`SessionState.awaitingApproval`). For failed, or
    /// an idle turn that stopped early, why.
    public var detail: String?

    public init(status: Status, reply: String? = nil, detail: String? = nil) {
        self.status = status
        self.reply = reply
        self.detail = detail
    }

    /// How a session reads as a task, the same wherever it runs. `state` is only read when a turn
    /// has run or runs, so callers may build it lazily.
    public init(
        phase: Phase, needsApproval: Bool, lastStopReason: StopReason?, agentName: String,
        state: @autoclosure () -> SessionState
    ) {
        switch phase {
        case .loading:
            self.init(status: .running)
        case .running where needsApproval:
            let state = state()
            self.init(status: .needsApproval, reply: state.latestReply, detail: state.awaitingApproval)
        case .running:
            self.init(status: .running, reply: state().latestReply)
        case .disconnected:
            self.init(status: .failed, reply: state().latestReply, detail: "\(agentName) stopped running.")
        case .idle:
            let state = state()
            let reply = state.latestReply
            switch lastStopReason {
            case nil, .endTurn: self.init(status: .idle, reply: reply)
            case .cancelled: self.init(status: .cancelled, reply: reply)
            case .error: self.init(status: .failed, reply: reply, detail: state.lastErrorNotice ?? "The turn failed.")
            case .maxTokens: self.init(status: .idle, reply: reply, detail: "stopped at the token limit")
            case .maxTurnRequests: self.init(status: .idle, reply: reply, detail: "stopped at the turn's request limit")
            case .refusal: self.init(status: .idle, reply: reply, detail: "the agent declined to continue")
            case .other(let reason): self.init(status: .idle, reply: reply, detail: "stopped: \(reason)")
            }
        }
    }

    /// How the task's card in its parent's transcript shows it, as an agent shows its own subagents.
    public var workState: SubagentWorkState {
        switch status {
        case .running: .running
        case .needsApproval: .requiresAction
        case .idle: .idle(stopReason: .endTurn, error: nil)
        case .cancelled: .idle(stopReason: .cancelled, error: nil)
        case .failed: .idle(stopReason: .error, error: RPCError(code: 0, message: detail ?? "The task failed."))
        }
    }
}
