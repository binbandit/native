import ACP
import Foundation

// The requests clients make about sessions: starting and opening them, following their events,
// sending messages, and answering what the agent asks. Agents' own requests are in HostAgents.swift.

public struct SyncAgentsParams: Codable, Sendable {
    public var agents: [AgentSpec]
    /// Read the user's login-shell environment again (after they installed an agent's CLI or signed
    /// in from a terminal). Agents started from then on get the new one.
    public var refreshEnvironment: Bool

    public init(agents: [AgentSpec], refreshEnvironment: Bool = false) {
        self.agents = agents
        self.refreshEnvironment = refreshEnvironment
    }
}

public struct NewSessionParams: Codable, Sendable {
    /// The id the session will have, chosen by the client so plugins can key per-session resources
    /// (MCP servers) by it before the session exists. Starting a session with an id the host
    /// already has returns that session, so a retry never starts two. Nil lets the host choose.
    public var sessionID: HostSessionID?
    public var agentID: String
    public var cwd: String
    public var parentID: HostSessionID?
    public var origin: SessionOrigin
    /// ACP `McpServer` objects for the agent, verbatim. The host hands them over again whenever it
    /// reloads the session.
    public var mcpServers: [JSONValue]
    /// The `_meta` sent with `session/new`, and with `session/load` whenever the host reloads it.
    public var meta: JSONValue?
    /// Follow the session's events from its first one, before the response arrives.
    public var attach: Bool

    public init(
        sessionID: HostSessionID? = nil, agentID: String, cwd: String, parentID: HostSessionID? = nil,
        origin: SessionOrigin = .user, mcpServers: [JSONValue] = [], meta: JSONValue? = nil, attach: Bool = false
    ) {
        self.sessionID = sessionID
        self.agentID = agentID
        self.cwd = cwd
        self.parentID = parentID
        self.origin = origin
        self.mcpServers = mcpServers
        self.meta = meta
        self.attach = attach
    }
}

/// Adopts a session the agent already has (one it listed), replaying it with `session/load`.
/// Opening the same agent session twice returns the same host session, without reloading it.
public struct OpenSessionParams: Codable, Sendable {
    /// As for `NewSessionParams`; ignored when the agent session is already open on the host.
    public var sessionID: HostSessionID?
    public var agentID: String
    public var agentSessionID: SessionID
    public var cwd: String
    public var title: String?
    public var parentID: HostSessionID?
    public var origin: SessionOrigin
    public var mcpServers: [JSONValue]
    public var meta: JSONValue?
    /// Follow the session's events. The answer then comes as soon as the session exists, with the
    /// replay streaming in after it; a load that fails leaves the session `disconnected` with its
    /// `problem` and a notice. Without it, the answer waits for the load and a failure throws.
    public var attach: Bool

    public init(
        sessionID: HostSessionID? = nil, agentID: String, agentSessionID: SessionID, cwd: String,
        title: String? = nil, parentID: HostSessionID? = nil, origin: SessionOrigin = .user,
        mcpServers: [JSONValue] = [], meta: JSONValue? = nil, attach: Bool = false
    ) {
        self.sessionID = sessionID
        self.agentID = agentID
        self.agentSessionID = agentSessionID
        self.cwd = cwd
        self.title = title
        self.parentID = parentID
        self.origin = origin
        self.mcpServers = mcpServers
        self.meta = meta
        self.attach = attach
    }
}

public struct SessionParams: Codable, Sendable {
    public var sessionID: HostSessionID

    public init(sessionID: HostSessionID) {
        self.sessionID = sessionID
    }
}

public struct CloseSessionParams: Codable, Sendable {
    public var sessionID: HostSessionID
    /// Also free the session in the agent's process (`session/close`), where the agent supports it.
    /// Its history stays with the agent either way.
    public var closeInAgent: Bool

    public init(sessionID: HostSessionID, closeInAgent: Bool = false) {
        self.sessionID = sessionID
        self.closeInAgent = closeInAgent
    }
}

/// Starts streaming a session's events to this client. With the `epoch` and last `seq` the client
/// saw, only what it missed is replayed; otherwise the whole log, from its `reset`.
public struct AttachParams: Codable, Sendable {
    public var sessionID: HostSessionID
    public var epoch: UUID?
    public var afterSeq: Int?

    public init(sessionID: HostSessionID, epoch: UUID? = nil, afterSeq: Int? = nil) {
        self.sessionID = sessionID
        self.epoch = epoch
        self.afterSeq = afterSeq
    }
}

/// The host replays the events as `_native/session/event` notifications before it answers, like
/// ACP's `session/load`, so when this arrives the client has applied all of them.
public struct AttachResult: Codable, Sendable {
    public var summary: HostSessionSummary

    public init(summary: HostSessionSummary) {
        self.summary = summary
    }
}

public struct PromptParams: Codable, Sendable {
    public var sessionID: HostSessionID
    /// Makes resubmitting safe: the host delivers each request id once and answers repeats with
    /// what it did the first time.
    public var requestID: UUID
    /// The user's words: what the transcript shows, and what recovery looks for in the agent's
    /// replay to tell whether the message arrived.
    public var text: String
    /// What goes to the agent, when it's more than `text`: attachments, images, linked files.
    public var content: [ContentBlock]?
    /// What the transcript shows went with the message.
    public var attachments: [EchoAttachment]
    /// Instructions to send ahead of the message, unless the agent already has these (the session's
    /// last delivered preamble has the same id when the turn starts).
    public var preamble: PromptPreambleSpec?
    public var behavior: PromptBehavior
    /// Whether the message shows in the transcript; messages other sessions send don't.
    public var echo: Bool
    public var origin: PromptEcho.Origin

    public init(
        sessionID: HostSessionID, requestID: UUID = UUID(), text: String, content: [ContentBlock]? = nil,
        attachments: [EchoAttachment] = [], preamble: PromptPreambleSpec? = nil, behavior: PromptBehavior = .queue,
        echo: Bool = true, origin: PromptEcho.Origin = .user
    ) {
        self.sessionID = sessionID
        self.requestID = requestID
        self.text = text
        self.content = content
        self.attachments = attachments
        self.preamble = preamble
        self.behavior = behavior
        self.echo = echo
        self.origin = origin
    }
}

public struct PromptResult: Codable, Sendable {
    public var delivery: PromptDelivery

    public init(delivery: PromptDelivery) {
        self.delivery = delivery
    }
}

public struct RespondPermissionParams: Codable, Sendable {
    public var sessionID: HostSessionID
    public var toolCallID: String
    /// Nil cancels the request.
    public var optionID: String?

    public init(sessionID: HostSessionID, toolCallID: String, optionID: String?) {
        self.sessionID = sessionID
        self.toolCallID = toolCallID
        self.optionID = optionID
    }
}

/// Answers a question the agent asked (`questionAsked`). The first client to answer wins.
public struct RespondQuestionParams: Codable, Sendable {
    public var sessionID: HostSessionID
    public var questionID: String
    /// ACP's `CreateElicitationResponse`, verbatim: `{"action": "accept", "content": {…}}`,
    /// `{"action": "decline"}` or `{"action": "cancel"}`.
    public var response: JSONValue

    public init(sessionID: HostSessionID, questionID: String, response: JSONValue) {
        self.sessionID = sessionID
        self.questionID = questionID
        self.response = response
    }
}

/// Runs a command such as `/context` as a turn the transcript doesn't show, and answers with the
/// agent's reply. Only while the session is idle.
public struct RunHiddenParams: Codable, Sendable {
    public var sessionID: HostSessionID
    public var text: String

    public init(sessionID: HostSessionID, text: String) {
        self.sessionID = sessionID
        self.text = text
    }
}

public struct RunHiddenResult: Codable, Sendable {
    public var output: String

    public init(output: String) {
        self.output = output
    }
}

public struct SetConfigOptionParams: Codable, Sendable {
    public var sessionID: HostSessionID
    public var configID: String
    public var value: String

    public init(sessionID: HostSessionID, configID: String, value: String) {
        self.sessionID = sessionID
        self.configID = configID
        self.value = value
    }
}

public struct QueueItemParams: Codable, Sendable {
    public var sessionID: HostSessionID
    public var itemID: UUID
    /// For `_native/queue/update`; emptying the text removes the item, unless it carries attachments.
    public var text: String?

    public init(sessionID: HostSessionID, itemID: UUID, text: String? = nil) {
        self.sessionID = sessionID
        self.itemID = itemID
        self.text = text
    }
}

/// Moves a queued message to just before another, or to the end.
public struct MoveQueuedParams: Codable, Sendable {
    public var sessionID: HostSessionID
    public var itemID: UUID
    public var before: UUID?

    public init(sessionID: HostSessionID, itemID: UUID, before: UUID?) {
        self.sessionID = sessionID
        self.itemID = itemID
        self.before = before
    }
}

/// Puts a message removed from the queue back where it was (undo). The host keeps what was removed
/// from each session's queue while it runs.
public struct RestoreQueuedParams: Codable, Sendable {
    public var sessionID: HostSessionID
    public var itemID: UUID
    public var index: Int

    public init(sessionID: HostSessionID, itemID: UUID, index: Int) {
        self.sessionID = sessionID
        self.itemID = itemID
        self.index = index
    }
}

public struct ListActivityParams: Codable, Sendable {
    /// Only entries after this one.
    public var after: Int64?
    public var limit: Int

    public init(after: Int64? = nil, limit: Int = 200) {
        self.after = after
        self.limit = limit
    }
}
