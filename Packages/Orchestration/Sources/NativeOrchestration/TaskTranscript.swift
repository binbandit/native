import ACP
import Foundation

/// The `session/update` payloads that show tasks in transcripts, for a runtime that writes
/// transcripts as JSON events (Native's host): a task's card in its parent's, as agents announce
/// their own subagents (the subagents RFD), and a message between sessions in both of theirs.
public enum TaskTranscript {
    /// Where a card's `_meta` says which of Native's tasks it shows, so a client can open the task
    /// as the session it is rather than as an agent's own subagent.
    public static let metaKey = "native.task"

    /// What a card's `_meta` names: the task, and where it runs.
    public struct CardMeta: Codable, Hashable, Sendable {
        public var taskID: String
        /// Native's id for the task's session (the host's session id).
        public var clientID: UUID
        public var agent: String

        public init(taskID: String, clientID: UUID, agent: String) {
            self.taskID = taskID
            self.clientID = clientID
            self.agent = agent
        }

        /// The card's `_meta` from a `subagent_update` payload, if it shows one of Native's tasks.
        public init?(update: JSONValue) {
            guard case .object(let meta)? = update["_meta"]?[TaskTranscript.metaKey],
                let taskID = meta["taskID"]?.stringValue, let agent = meta["agent"]?.stringValue,
                let clientID = meta["clientID"]?.stringValue.flatMap(UUID.init(uuidString:))
            else { return nil }
            self.init(taskID: taskID, clientID: clientID, agent: agent)
        }

        var json: JSONValue {
            .object([
                "taskID": .string(taskID), "clientID": .string(clientID.uuidString), "agent": .string(agent),
            ])
        }
    }

    /// The task's card: its title and agent once (`title` non-nil), then just its state.
    public static func card(
        session: SessionID, title: String? = nil, agentName: String? = nil, state: SubagentWorkState,
        meta: CardMeta
    ) -> JSONValue {
        var update: [String: JSONValue] = [
            "sessionUpdate": .string("subagent_update"), "sessionId": .string(session.rawValue), "state": state.json,
            "_meta": .object([metaKey: meta.json]),
        ]
        if let title {
            update["title"] = .string(title)
            update["capabilities"] = .object(["cancel": .object([:])])
        }
        if let agentName {
            update["description"] = .string(agentName)
        }
        return .object(update)
    }

    /// A message from one session to another, as either transcript shows it. Every transcript gets
    /// its own copy, so each needs its own id.
    public static func message(_ text: String, from sender: SessionID, to recipient: SessionID) -> JSONValue {
        .object([
            "sessionUpdate": .string("session_message"), "messageId": .string("native-\(UUID().uuidString)"),
            "senderSessionId": .string(sender.rawValue), "recipientSessionId": .string(recipient.rawValue),
            "content": .array([.object(["type": .string("text"), "text": .string(text)])]),
        ])
    }
}

extension SubagentWorkState {
    /// As the subagents RFD sends it.
    var json: JSONValue {
        let name: String
        var fields: [String: JSONValue] = [:]
        switch self {
        case .running: name = "running"
        case .requiresAction: name = "requires_action"
        case .unknown: name = "unknown"
        case .other(let state): name = state
        case .idle(let stopReason, let error):
            name = "idle"
            fields["stopReason"] = stopReason.map { .string($0.wireName) }
            fields["error"] = error.map { .object(["code": .number(Double($0.code)), "message": .string($0.message)]) }
        }
        fields["state"] = .string(name)
        return .object(fields)
    }
}

extension StopReason {
    /// The ACP name.
    var wireName: String {
        switch self {
        case .endTurn: "end_turn"
        case .maxTokens: "max_tokens"
        case .maxTurnRequests: "max_turn_requests"
        case .refusal: "refusal"
        case .cancelled: "cancelled"
        case .error: "error"
        case .other(let reason): reason
        }
    }
}
