import ACP
import Foundation

/// A string enum on the wire that tolerates values from a newer peer: anything it doesn't know
/// decodes as `unknown` instead of failing the whole message.
public protocol WireEnum: RawRepresentable, Codable, Hashable, Sendable where RawValue == String {
    static var unknown: Self { get }
}

extension WireEnum {
    public init(from decoder: any Decoder) throws {
        self = Self(rawValue: try decoder.singleValueContainer().decode(String.self)) ?? .unknown
    }
}

/// Native's identity for a session, assigned by the host when the session opens and kept for good.
/// It's the `SessionContext.clientID` plugins key per-session resources by, and the session id
/// clients address the session with; the agent's own id for it is `HostSessionSummary.agentSessionID`.
public struct HostSessionID: Hashable, Sendable, Codable, CustomStringConvertible {
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

/// How to launch an agent that speaks ACP over stdio. Mirrors a plugin's `AgentManifest`; clients
/// hand the host their agents until the plugin registry moves into the host.
public struct AgentSpec: Codable, Hashable, Sendable, Identifiable {
    public var id: String
    public var name: String
    /// Looked up on the user's login-shell PATH, or an absolute path.
    public var command: String
    public var args: [String]
    public var env: [String: String]
    /// Variables to set to the absolute path of a command on the user's PATH, such as
    /// `{"CLAUDE_CODE_EXECUTABLE": "claude"}`.
    public var resolveExecutables: [String: String]

    public init(id: String, name: String, command: String, args: [String] = [], env: [String: String] = [:], resolveExecutables: [String: String] = [:]) {
        self.id = id
        self.name = name
        self.command = command
        self.args = args
        self.env = env
        self.resolveExecutables = resolveExecutables
    }
}

public enum SessionOrigin: String, WireEnum {
    /// The user's own session.
    case user
    /// Started by Native's tools for another session (orchestration) or for none (a workflow step).
    case task
    /// Announced by its agent as a subagent of another session.
    case announced
    case unknown
}

public enum HostSessionPhase: String, WireEnum {
    /// Replaying history from the agent.
    case loading
    case idle
    case prompting
    /// Coming back from an interruption: the agent is being restarted and the session reloaded.
    case recovering
    /// The agent can't run (not installed, signed out, keeps crashing); `problem` says why.
    case disconnected
    case unknown
}

/// How a message sent while a turn runs should be delivered.
public enum PromptBehavior: String, WireEnum {
    /// Wait for the running turn to end.
    case queue
    /// Join the running turn, where the agent supports it; otherwise queue.
    case steer
    case unknown
}

/// What became of a message sent with `session/prompt`.
public enum PromptDelivery: String, WireEnum {
    /// It started a turn of its own.
    case prompted
    /// It joined the turn that was running.
    case steered
    /// It waits for the running turn to end.
    case queued
    case unknown
}

/// A message waiting for the running turn to end.
public struct QueuedPrompt: Codable, Hashable, Sendable, Identifiable {
    public var id: UUID
    public var text: String
    /// Whether it shows in the transcript when it goes out.
    public var isEchoed: Bool

    public init(id: UUID = UUID(), text: String, isEchoed: Bool = true) {
        self.id = id
        self.text = text
        self.isEchoed = isEchoed
    }
}

/// What every client knows about a session the host has open, whether or not it's attached.
public struct HostSessionSummary: Codable, Hashable, Sendable, Identifiable {
    public var id: HostSessionID
    public var agentID: String
    public var agentName: String
    /// The agent's id for the session; nil while `session/new` is in flight.
    public var agentSessionID: SessionID?
    public var cwd: String
    public var parentID: HostSessionID?
    public var origin: SessionOrigin
    /// The agent's title for the session, if it gave one.
    public var title: String?
    public var phase: HostSessionPhase
    public var needsApproval: Bool
    public var queue: [QueuedPrompt]
    /// Queued messages wait out a cancelled or failed turn until the user sends again.
    public var isQueuePaused: Bool
    public var supportsSteering: Bool
    public var lastActivity: Date?
    /// How the latest turn ended (an ACP stop reason, or "error"); nil before the first one.
    public var lastStopReason: String?
    /// Why the session can't continue right now, for `disconnected`.
    public var problem: String?

    public init(
        id: HostSessionID, agentID: String, agentName: String, agentSessionID: SessionID?, cwd: String, parentID: HostSessionID? = nil,
        origin: SessionOrigin = .user, title: String? = nil, phase: HostSessionPhase, needsApproval: Bool = false, queue: [QueuedPrompt] = [],
        isQueuePaused: Bool = false, supportsSteering: Bool = false, lastActivity: Date? = nil, lastStopReason: String? = nil, problem: String? = nil
    ) {
        self.id = id
        self.agentID = agentID
        self.agentName = agentName
        self.agentSessionID = agentSessionID
        self.cwd = cwd
        self.parentID = parentID
        self.origin = origin
        self.title = title
        self.phase = phase
        self.needsApproval = needsApproval
        self.queue = queue
        self.isQueuePaused = isQueuePaused
        self.supportsSteering = supportsSteering
        self.lastActivity = lastActivity
        self.lastStopReason = lastStopReason
        self.problem = problem
    }

    /// Whether a turn is running or about to (recovery resumes one).
    public var isWorking: Bool {
        phase == .prompting || phase == .recovering
    }
}
