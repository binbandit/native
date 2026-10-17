import Foundation

/// An ACP patch field: omitted leaves the stored value alone, `null` clears it, and a value
/// replaces it.
public enum Patch<Value: Hashable & Sendable>: Hashable, Sendable {
    case unchanged
    case cleared
    case set(Value)

    public func applied(to current: Value?) -> Value? {
        switch self {
        case .unchanged: current
        case .cleared: nil
        case .set(let value): value
        }
    }
}

extension KeyedDecodingContainer {
    func decodePatch<Value: Decodable>(_ type: Value.Type, forKey key: Key) throws -> Patch<Value> {
        guard contains(key) else { return .unchanged }
        if try decodeNil(forKey: key) { return .cleared }
        return .set(try decode(Value.self, forKey: key))
    }
}

/// Announces or updates a subagent session the agent created, sent on its parent's stream
/// (the subagents RFD). The child's own updates arrive under its session id.
public struct SubagentUpdate: Decodable, Hashable, Sendable {
    /// The child session.
    public var sessionId: SessionID
    public var title: Patch<String>
    public var description: Patch<String>
    /// Whether the client may cancel the child's current work with `session/cancel`.
    public var canCancel: Patch<Bool>
    public var state: Patch<SubagentWorkState>

    /// For clients that run subagents themselves, such as tasks one agent hands another, and show
    /// them the way agents' own subagents are shown.
    public init(sessionId: SessionID, title: Patch<String> = .unchanged, description: Patch<String> = .unchanged, canCancel: Patch<Bool> = .unchanged, state: Patch<SubagentWorkState> = .unchanged) {
        self.sessionId = sessionId
        self.title = title
        self.description = description
        self.canCancel = canCancel
        self.state = state
    }

    private enum CodingKeys: String, CodingKey {
        case sessionId, title, description, capabilities, state
    }

    private struct Capabilities: Decodable, Hashable, Sendable {
        var cancel: JSONValue?
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        sessionId = try container.decode(SessionID.self, forKey: .sessionId)
        title = try container.decodePatch(String.self, forKey: .title)
        description = try container.decodePatch(String.self, forKey: .description)
        state = try container.decodePatch(SubagentWorkState.self, forKey: .state)
        // Capabilities are replaced as a whole; a missing or null `cancel` means it's unsupported.
        canCancel = switch try container.decodePatch(Capabilities.self, forKey: .capabilities) {
        case .unchanged: .unchanged
        case .cleared: .set(false)
        case .set(let capabilities): .set(capabilities.cancel.map { $0 != .null } ?? false)
        }
    }
}

// MARK: - The RFD's earlier draft

extension SubagentUpdate {
    private enum DraftKeys: String, CodingKey {
        case subagentSessionId, name, task, state
    }

    /// `subagent_spawned`: a child with a name and its task, which starts working right away.
    init(spawned decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: DraftKeys.self)
        self.init(
            sessionId: try container.decode(SessionID.self, forKey: .subagentSessionId),
            title: try container.decodeIfPresent(String.self, forKey: .name).map(Patch.set) ?? .unchanged,
            description: try container.decodeIfPresent(String.self, forKey: .task).map(Patch.set) ?? .unchanged,
            canCancel: .set(false),
            state: .set(.running)
        )
    }

    /// `subagent_state_update`: a terminal state as a plain string.
    init(stateChange decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: DraftKeys.self)
        let state: SubagentWorkState = switch try container.decode(String.self, forKey: .state) {
        case "completed": .idle(stopReason: .endTurn, error: nil)
        case "failed": .idle(stopReason: .error, error: nil)
        case "cancelled": .idle(stopReason: .cancelled, error: nil)
        case "disconnected": .unknown
        case let other: .other(other)
        }
        self.init(sessionId: try container.decode(SessionID.self, forKey: .subagentSessionId), state: .set(state))
    }
}

/// What a subagent is doing right now. It isn't a lifecycle: an idle child can be given more work.
public enum SubagentWorkState: Hashable, Sendable, Decodable {
    case running
    /// Blocked on the user, typically a permission request in the child session.
    case requiresAction
    case idle(stopReason: StopReason?, error: RPCError?)
    /// The agent lost track of the child; earlier activity is no longer confirmed.
    case unknown
    /// A state this client doesn't know, preserved as sent.
    case other(String)

    private enum CodingKeys: String, CodingKey {
        case state, stopReason, error
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let state = try container.decode(String.self, forKey: .state)
        self = switch state {
        case "running": .running
        case "requires_action": .requiresAction
        case "idle": .idle(
            stopReason: try container.decodeIfPresent(StopReason.self, forKey: .stopReason),
            error: try container.decodeIfPresent(RPCError.self, forKey: .error)
        )
        case "unknown": .unknown
        default: .other(state)
        }
    }

    public var isWorking: Bool {
        self == .running || self == .requiresAction
    }
}

/// A message one session sent another, as seen in the transcript the update is addressed to.
/// The outer session matches the sender (outgoing) or the recipient (incoming).
public struct SessionMessageUpdate: Decodable, Hashable, Sendable {
    public var messageId: String
    public var senderSessionId: SessionID?
    public var recipientSessionId: SessionID?
    public var content: Patch<[ContentBlock]>

    /// For clients that relay messages between sessions themselves, such as tasks of different
    /// agents talking to each other, and show them like agents' own.
    public init(messageId: String, senderSessionId: SessionID?, recipientSessionId: SessionID?, content: [ContentBlock]) {
        self.messageId = messageId
        self.senderSessionId = senderSessionId
        self.recipientSessionId = recipientSessionId
        self.content = .set(content)
    }

    private enum CodingKeys: String, CodingKey {
        case messageId, senderSessionId, recipientSessionId, content
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        messageId = try container.decode(String.self, forKey: .messageId)
        senderSessionId = try container.decodeIfPresent(SessionID.self, forKey: .senderSessionId)
        recipientSessionId = try container.decodeIfPresent(SessionID.self, forKey: .recipientSessionId)
        content = try container.decodePatch([ContentBlock].self, forKey: .content)
    }
}

/// Appends one block to a session message, creating the message if it's new.
public struct SessionMessageChunk: Decodable, Hashable, Sendable {
    public var messageId: String
    public var senderSessionId: SessionID?
    public var recipientSessionId: SessionID?
    public var content: ContentBlock
}
