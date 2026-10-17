import ACP
import Foundation

/// The Native Host Protocol: JSON-RPC 2.0 over newline-delimited JSON, the framing ACP uses over
/// stdio. Methods follow ACP's names where they mean the same thing; Native's own are under
/// `_native/`. See `docs/durability.md`.
public enum HostProtocol {
    /// Bumped on any incompatible change. A client that finds an older host asks it to restart
    /// (into the newer binary that came with the app) once it's idle.
    public static let version = 1

    public enum Method {
        // Client → host requests.
        public static let initialize = "initialize"
        public static let syncAgents = "_native/agents/sync"
        public static let listSessions = "session/list"
        public static let newSession = "session/new"
        public static let openSession = "_native/session/open"
        public static let attach = "_native/session/attach"
        public static let detach = "_native/session/detach"
        public static let prompt = "session/prompt"
        public static let cancel = "session/cancel"
        public static let setConfigOption = "session/set_config_option"
        public static let respondPermission = "_native/session/respond_permission"
        public static let closeSession = "_native/session/close"
        public static let updateQueued = "_native/queue/update"
        public static let removeQueued = "_native/queue/remove"
        public static let sendQueuedNow = "_native/queue/send_now"
        public static let listActivity = "_native/activity/list"
        public static let shutdown = "_native/host/shutdown"

        // Host → client notifications.
        public static let sessionEvent = "_native/session/event"
        public static let sessionChanged = "_native/session/changed"
        public static let sessionClosed = "_native/session/closed"
        public static let activity = "_native/activity"
    }
}

// MARK: - Handshake

public struct PeerInfo: Codable, Hashable, Sendable {
    public var name: String
    public var version: String
    public var build: String

    public init(name: String, version: String, build: String) {
        self.name = name
        self.version = version
        self.build = build
    }
}

public struct InitializeParams: Codable, Sendable {
    public var protocolVersion: Int
    public var clientInfo: PeerInfo

    public init(protocolVersion: Int = HostProtocol.version, clientInfo: PeerInfo) {
        self.protocolVersion = protocolVersion
        self.clientInfo = clientInfo
    }
}

/// A machine's host, as clients address it. Stable for the life of the host's store, so a project
/// on a Mac mini stays on that Mac mini whatever network path reaches it.
public struct HostID: Hashable, Sendable, Codable, CustomStringConvertible {
    public let rawValue: UUID

    public init(_ rawValue: UUID = UUID()) {
        self.rawValue = rawValue
    }

    public init(from decoder: any Decoder) throws {
        rawValue = try decoder.singleValueContainer().decode(UUID.self)
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }

    public var description: String { rawValue.uuidString }
}

public struct HostInfo: Codable, Hashable, Sendable {
    public var protocolVersion: Int
    public var hostID: HostID
    /// The machine's name, for telling hosts apart ("Brayden's MacBook Pro", "mini").
    public var machineName: String
    public var hostInfo: PeerInfo
    /// Changes every time the host process starts; session sequence numbers are only comparable
    /// within one epoch.
    public var epoch: UUID
    public var processID: Int32
    public var startedAt: Date
    public var channel: String

    public init(protocolVersion: Int, hostID: HostID, machineName: String, hostInfo: PeerInfo, epoch: UUID, processID: Int32, startedAt: Date, channel: String) {
        self.protocolVersion = protocolVersion
        self.hostID = hostID
        self.machineName = machineName
        self.hostInfo = hostInfo
        self.epoch = epoch
        self.processID = processID
        self.startedAt = startedAt
        self.channel = channel
    }
}

// MARK: - Requests

public struct SyncAgentsParams: Codable, Sendable {
    public var agents: [AgentSpec]

    public init(agents: [AgentSpec]) {
        self.agents = agents
    }
}

public struct NewSessionParams: Codable, Sendable {
    public var agentID: String
    public var cwd: String
    public var parentID: HostSessionID?
    public var origin: SessionOrigin
    /// ACP `McpServer` objects for the agent, verbatim. The host hands them over again whenever it
    /// reloads the session.
    public var mcpServers: [JSONValue]

    public init(agentID: String, cwd: String, parentID: HostSessionID? = nil, origin: SessionOrigin = .user, mcpServers: [JSONValue] = []) {
        self.agentID = agentID
        self.cwd = cwd
        self.parentID = parentID
        self.origin = origin
        self.mcpServers = mcpServers
    }
}

/// Adopts a session the agent already has (one it listed), replaying it with `session/load`.
/// Opening the same agent session twice returns the same host session.
public struct OpenSessionParams: Codable, Sendable {
    public var agentID: String
    public var agentSessionID: SessionID
    public var cwd: String
    public var title: String?
    public var mcpServers: [JSONValue]

    public init(agentID: String, agentSessionID: SessionID, cwd: String, title: String? = nil, mcpServers: [JSONValue] = []) {
        self.agentID = agentID
        self.agentSessionID = agentSessionID
        self.cwd = cwd
        self.title = title
        self.mcpServers = mcpServers
    }
}

public struct SessionParams: Codable, Sendable {
    public var sessionID: HostSessionID

    public init(sessionID: HostSessionID) {
        self.sessionID = sessionID
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
    public var text: String
    public var behavior: PromptBehavior
    /// Whether the message shows in the transcript; messages other sessions send don't.
    public var echo: Bool
    public var origin: PromptEcho.Origin

    public init(sessionID: HostSessionID, requestID: UUID = UUID(), text: String, behavior: PromptBehavior = .queue, echo: Bool = true, origin: PromptEcho.Origin = .user) {
        self.sessionID = sessionID
        self.requestID = requestID
        self.text = text
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
    /// For `_native/queue/update`; emptying the text removes the item.
    public var text: String?

    public init(sessionID: HostSessionID, itemID: UUID, text: String? = nil) {
        self.sessionID = sessionID
        self.itemID = itemID
        self.text = text
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

public struct ShutdownParams: Codable, Sendable {
    /// Stop agents now, cancelling their turns ("Quit Native and Stop Agents"). Otherwise the host
    /// exits once nothing is running, and launchd brings the new binary up (an update).
    public var stopAgents: Bool

    public init(stopAgents: Bool) {
        self.stopAgents = stopAgents
    }
}

public struct EmptyMessage: Codable, Sendable {
    public init() {}
}

// MARK: - Notifications

public struct SessionEventNotification: Codable, Sendable {
    public var sessionID: HostSessionID
    public var event: HostEvent

    public init(sessionID: HostSessionID, event: HostEvent) {
        self.sessionID = sessionID
        self.event = event
    }
}

public struct SessionChangedNotification: Codable, Sendable {
    public var summary: HostSessionSummary

    public init(summary: HostSessionSummary) {
        self.summary = summary
    }
}

// MARK: - Activity

/// Something that happened to a session, kept so the user can see what went on while they were
/// away: finished turns, approvals asked for, interruptions recovered from.
public struct ActivityEntry: Codable, Hashable, Sendable, Identifiable {
    public enum Kind: String, WireEnum {
        case turnFinished
        case turnFailed
        case approvalNeeded
        case recovered
        case hostStarted
        case unknown
    }

    public var id: Int64
    public var at: Date
    public var sessionID: HostSessionID?
    public var kind: Kind
    /// The session's title or agent, at the time.
    public var subject: String?
    public var detail: String?
    public var recovery: RecoveryNote?

    public init(id: Int64, at: Date, sessionID: HostSessionID?, kind: Kind, subject: String? = nil, detail: String? = nil, recovery: RecoveryNote? = nil) {
        self.id = id
        self.at = at
        self.sessionID = sessionID
        self.kind = kind
        self.subject = subject
        self.detail = detail
        self.recovery = recovery
    }
}
