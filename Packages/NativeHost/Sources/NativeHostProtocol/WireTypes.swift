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
    /// Commands besides `command` that must be on the PATH, such as the CLI an adapter drives
    /// (`claude` for an `npx` adapter). The host doctor checks them.
    public var requires: [String]
    /// The command that installs the agent's CLI, from its plugin: the doctor's fix when it's missing.
    public var install: String?
    /// Sign-in methods the agent accepts without advertising them, from its plugin (an API key in
    /// a variable it reads). The host sets only the variables these and the agent's own name.
    public var authMethods: [AuthMethod]
    /// Seconds a session may sit with nothing happening before the host unloads it from the agent,
    /// keeping its transcript to resume quietly; once none is loaded, the agent's process ends too
    /// (`HostCore+IdleUnload.swift`). Nil keeps sessions loaded.
    public var idleUnloadTimeout: Int?
    /// A command that names a session in the agent without asking a model (`/rename`), which the
    /// host sends ahead of turns to keep the agent's name for it in step with Native's title
    /// (`HostCore+AgentNames.swift`). Nil leaves names to the agent.
    public var renameCommand: String?

    public init(
        id: String, name: String, command: String, args: [String] = [], env: [String: String] = [:],
        resolveExecutables: [String: String] = [:], requires: [String] = [], install: String? = nil,
        authMethods: [AuthMethod] = [], idleUnloadTimeout: Int? = nil, renameCommand: String? = nil
    ) {
        self.id = id
        self.name = name
        self.command = command
        self.args = args
        self.env = env
        self.resolveExecutables = resolveExecutables
        self.requires = requires
        self.install = install
        self.authMethods = authMethods
        self.idleUnloadTimeout = idleUnloadTimeout
        self.renameCommand = renameCommand
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, command, args, env, resolveExecutables, requires, install, authMethods, idleUnloadTimeout
        case renameCommand
    }

    // `requires`, `install`, `authMethods`, `idleUnloadTimeout` and `renameCommand` came later: specs
    // stored by older hosts and sent by older apps lack them.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        command = try container.decode(String.self, forKey: .command)
        args = try container.decode([String].self, forKey: .args)
        env = try container.decode([String: String].self, forKey: .env)
        resolveExecutables = try container.decode([String: String].self, forKey: .resolveExecutables)
        requires = try container.decodeIfPresent([String].self, forKey: .requires) ?? []
        install = try container.decodeIfPresent(String.self, forKey: .install)
        authMethods = try container.decodeIfPresent([AuthMethod].self, forKey: .authMethods) ?? []
        idleUnloadTimeout = try container.decodeIfPresent(Int.self, forKey: .idleUnloadTimeout)
        renameCommand = try container.decodeIfPresent(String.self, forKey: .renameCommand)
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

/// A message waiting for the running turn to end. Its id is the request id it was sent with.
public struct QueuedPrompt: Codable, Hashable, Sendable, Identifiable {
    public var id: UUID
    public var text: String
    /// Whether it shows in the transcript when it goes out.
    public var isEchoed: Bool
    /// What goes with it, as the transcript will show it; without images in summaries.
    public var attachments: [EchoAttachment]

    public init(id: UUID = UUID(), text: String, isEchoed: Bool = true, attachments: [EchoAttachment] = []) {
        self.id = id
        self.text = text
        self.isEchoed = isEchoed
        self.attachments = attachments
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
    /// Stop was asked for and the agent hasn't ended the turn yet. Asking again more than a second
    /// later, or the agent staying silent for ten, ends it on the host's side.
    public var isStopping: Bool
    /// A hidden command (`_native/session/run_hidden`) is running: the session looks idle, but new
    /// messages queue.
    public var isRunningHiddenCommand: Bool
    /// When a prompt that failed for a passing reason (the network, an overloaded provider) goes out
    /// again. Cancelling stops the retry and leaves the message queued.
    public var retryAt: Date?
    /// Native's titles for the session (the user's, the generated one), from hosts that keep them.
    public var titles: HostSessionTitles?
    /// Whether the host waits for this session before restarting for an update, as it reported it:
    /// a turn, a hidden command, a load (a quiet one too) or background work. Nil from hosts that
    /// don't report it; `holdsRestart` reads it.
    public var isHoldingRestart: Bool?

    public init(
        id: HostSessionID, agentID: String, agentName: String, agentSessionID: SessionID?, cwd: String,
        parentID: HostSessionID? = nil,
        origin: SessionOrigin = .user, title: String? = nil, phase: HostSessionPhase, needsApproval: Bool = false,
        queue: [QueuedPrompt] = [],
        isQueuePaused: Bool = false, supportsSteering: Bool = false, lastActivity: Date? = nil,
        lastStopReason: String? = nil, problem: String? = nil, isStopping: Bool = false,
        isRunningHiddenCommand: Bool = false, retryAt: Date? = nil, titles: HostSessionTitles? = nil,
        isHoldingRestart: Bool? = nil
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
        self.isStopping = isStopping
        self.isRunningHiddenCommand = isRunningHiddenCommand
        self.retryAt = retryAt
        self.titles = titles
        self.isHoldingRestart = isHoldingRestart
    }

    /// Whether a turn is running or about to (recovery resumes one, a retry sends one).
    public var isWorking: Bool {
        phase == .prompting || phase == .recovering || retryAt != nil
    }

    /// Whether restarting the host now would interrupt something here, so an update waits for it.
    /// A host that doesn't report it is judged by what its summary does say.
    public var holdsRestart: Bool {
        isHoldingRestart ?? (isWorking || isRunningHiddenCommand || phase == .loading)
    }
}
