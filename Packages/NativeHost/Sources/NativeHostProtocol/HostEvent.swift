import ACP
import Foundation

/// One entry in a session's ordered log, as the host streams it to attached clients. Folding the log
/// from its first entry (`SessionMirror`) rebuilds the session exactly, on any client.
///
/// Agents' own `session/update`s travel verbatim, so clients run them through the same ACP reducer
/// the agent's other clients would; everything else is a fact only Native knows (what it sent, what
/// the user approved, how a turn ended, what it recovered from).
public struct HostEvent: Codable, Hashable, Sendable {
    /// Increases by one per event within a session, across reloads, for as long as the host runs.
    public var seq: Int
    public var at: Date
    public var payload: Payload

    public init(seq: Int, at: Date = .now, payload: Payload) {
        self.seq = seq
        self.at = at
        self.payload = payload
    }

    public enum Payload: Hashable, Sendable {
        /// The transcript starts over: the session is being (re)loaded from the agent, which replays
        /// it until `loaded`. Clients drop what they had.
        case reset(loading: Bool)
        /// The replay that followed `reset(loading: true)` is complete.
        case loaded
        /// An agent's `session/update` payload (the `update` object), as it sent it.
        case update(JSONValue)
        /// A message Native delivered to the agent: a turn's prompt (shown or not) or a steer.
        case prompt(PromptEcho)
        /// The agent asks the user to approve a tool call. `request` is the ACP
        /// `session/request_permission` params, verbatim.
        case permissionRequested(toolCallID: String, request: JSONValue)
        /// Answered (by any client) or withdrawn (the turn was cancelled, or the agent went away).
        case permissionResolved(toolCallID: String, optionID: String?)
        /// The agent asks the user to fill in a form (`elicitation/create`). `request` is its params,
        /// verbatim; answer with `_native/session/respond_question`.
        case questionAsked(questionID: String, request: JSONValue)
        /// Answered (by any client) or withdrawn (the turn was cancelled, or the agent went away).
        case questionResolved(questionID: String)
        /// An ACP stop reason, such as `end_turn` or `cancelled`.
        case turnEnded(stopReason: String)
        /// The prompt request failed instead of ending with a stop reason. `error` is the agent's
        /// JSON-RPC error, verbatim, when it sent one (`auth_required`, usage-limit data).
        case turnFailed(message: String, error: RPCError?)
        case notice(text: String, isError: Bool)
        /// The session's turn was cut off and Native did something about it.
        case recovered(RecoveryNote)
        /// An event from a newer host that this client doesn't understand; safe to ignore.
        case unsupported(type: String)
    }
}

/// What interrupted a session's turn, and what Native did about it. Clients phrase it for people
/// ("Claude Code stopped unexpectedly at 2:14 PM. Native restarted it and resumed your task.").
public struct RecoveryNote: Codable, Hashable, Sendable {
    public enum Cause: String, WireEnum {
        /// The agent process exited while the host kept running.
        case agentStopped
        /// The user restarted the agent (`_native/agents/restart`).
        case agentRestarted
        /// The host process itself stopped (crashed or was killed) and launchd restarted it.
        case hostStopped
        /// The host restarted onto a newer Native ("Restart Host Now" after an update).
        case hostUpdated
        /// The Mac restarted or the user logged out.
        case systemRestarted
        case unknown
    }

    public enum Action: String, WireEnum {
        /// The agent had the prompt; it was told the turn was interrupted and asked to continue.
        case resumed
        /// The prompt never reached the agent, so it was sent again.
        case resent
        /// It kept failing, so Native stopped retrying; the user's next message continues.
        case paused
        /// The agent couldn't be started again; `RecoveryNote.problem` says why.
        case failed
        case unknown
    }

    public var cause: Cause
    public var action: Action
    public var agentName: String
    /// When the interruption happened, as closely as Native knows it.
    public var interruptedAt: Date
    public var problem: String?

    public init(cause: Cause, action: Action, agentName: String, interruptedAt: Date, problem: String? = nil) {
        self.cause = cause
        self.action = action
        self.agentName = agentName
        self.interruptedAt = interruptedAt
        self.problem = problem
    }

    /// The sentence a person reads, such as "Claude Code stopped unexpectedly at 2:14 PM. Native
    /// restarted it and resumed your task."
    public func sentence(
        formattingTime format: (Date) -> String = { $0.formatted(date: .omitted, time: .shortened) }
    ) -> String {
        let time = format(interruptedAt)
        let what =
            switch cause {
            case .agentStopped, .unknown: "\(agentName) stopped unexpectedly at \(time)."
            case .agentRestarted: "You restarted \(agentName) at \(time)."
            case .hostStopped: "Native's background host stopped unexpectedly at \(time)."
            case .hostUpdated: "Native's background host restarted at \(time) to update."
            case .systemRestarted: "Your Mac restarted at \(time) while \(agentName) was working."
            }
        let did =
            switch action {
            case .resumed where cause == .agentRestarted: "Native asked it to pick up where it left off."
            case .resumed: "Native restarted \(agentName) and asked it to pick up where it left off."
            case .resent: "Your message hadn't reached \(agentName) yet, so Native sent it again."
            case .paused: "It kept stopping, so Native paused this task. Send a message to continue."
            case .failed: "Native couldn't restart \(agentName)\(problem.map { ": \($0)" } ?? ".")"
            case .unknown: "Native recovered the session."
            }
        return "\(what) \(did)"
    }
}

// MARK: - Coding

extension HostEvent {
    private enum CodingKeys: String, CodingKey {
        case seq, at, type, loading, update, prompt, toolCallID, request, optionID, questionID, stopReason, message,
            error, text, isError, recovery
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        seq = try container.decode(Int.self, forKey: .seq)
        at = try container.decode(Date.self, forKey: .at)
        let type = try container.decode(String.self, forKey: .type)
        payload =
            switch type {
            case "reset": .reset(loading: try container.decode(Bool.self, forKey: .loading))
            case "loaded": .loaded
            case "update": .update(try container.decodeJSON(forKey: .update))
            case "prompt": .prompt(try container.decode(PromptEcho.self, forKey: .prompt))
            case "permission_requested":
                .permissionRequested(
                    toolCallID: try container.decode(String.self, forKey: .toolCallID),
                    request: try container.decodeJSON(forKey: .request))
            case "permission_resolved":
                .permissionResolved(
                    toolCallID: try container.decode(String.self, forKey: .toolCallID),
                    optionID: try container.decodeIfPresent(String.self, forKey: .optionID))
            case "question_asked":
                .questionAsked(
                    questionID: try container.decode(String.self, forKey: .questionID),
                    request: try container.decodeJSON(forKey: .request))
            case "question_resolved":
                .questionResolved(questionID: try container.decode(String.self, forKey: .questionID))
            case "turn_ended": .turnEnded(stopReason: try container.decode(String.self, forKey: .stopReason))
            case "turn_failed":
                .turnFailed(
                    message: try container.decode(String.self, forKey: .message),
                    error: try container.decodeIfPresent(RPCError.self, forKey: .error))
            case "notice":
                .notice(
                    text: try container.decode(String.self, forKey: .text),
                    isError: try container.decode(Bool.self, forKey: .isError))
            case "recovered": .recovered(try container.decode(RecoveryNote.self, forKey: .recovery))
            default: .unsupported(type: type)
            }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(seq, forKey: .seq)
        try container.encode(at, forKey: .at)
        switch payload {
        case .reset(let loading):
            try container.encode("reset", forKey: .type)
            try container.encode(loading, forKey: .loading)
        case .loaded:
            try container.encode("loaded", forKey: .type)
        case .update(let update):
            try container.encode("update", forKey: .type)
            try container.encode(update, forKey: .update)
        case .prompt(let prompt):
            try container.encode("prompt", forKey: .type)
            try container.encode(prompt, forKey: .prompt)
        case .permissionRequested(let toolCallID, let request):
            try container.encode("permission_requested", forKey: .type)
            try container.encode(toolCallID, forKey: .toolCallID)
            try container.encode(request, forKey: .request)
        case .permissionResolved(let toolCallID, let optionID):
            try container.encode("permission_resolved", forKey: .type)
            try container.encode(toolCallID, forKey: .toolCallID)
            try container.encodeIfPresent(optionID, forKey: .optionID)
        case .questionAsked(let questionID, let request):
            try container.encode("question_asked", forKey: .type)
            try container.encode(questionID, forKey: .questionID)
            try container.encode(request, forKey: .request)
        case .questionResolved(let questionID):
            try container.encode("question_resolved", forKey: .type)
            try container.encode(questionID, forKey: .questionID)
        case .turnEnded(let stopReason):
            try container.encode("turn_ended", forKey: .type)
            try container.encode(stopReason, forKey: .stopReason)
        case .turnFailed(let message, let error):
            try container.encode("turn_failed", forKey: .type)
            try container.encode(message, forKey: .message)
            try container.encodeIfPresent(error, forKey: .error)
        case .notice(let text, let isError):
            try container.encode("notice", forKey: .type)
            try container.encode(text, forKey: .text)
            try container.encode(isError, forKey: .isError)
        case .recovered(let note):
            try container.encode("recovered", forKey: .type)
            try container.encode(note, forKey: .recovery)
        case .unsupported(let type):
            try container.encode(type, forKey: .type)
        }
    }
}
