import ACP
import Foundation

/// The Native Host Protocol: JSON-RPC 2.0 over newline-delimited JSON, the framing ACP uses over
/// stdio. Methods follow ACP's names where they mean the same thing; Native's own are under
/// `_native/`. See `docs/durability.md`.
public enum HostProtocol {
    /// Bumped on any incompatible change. A client that finds an older host asks it to restart
    /// (into the newer binary that came with the app) once it's idle.
    ///
    /// The handshake never changes, whatever the version: `initialize`, the `protocolVersion` and
    /// `hostInfo` of its result (`FrozenHandshake`), and `_native/host/shutdown` with
    /// `stopAgents: false`. That's what lets any newer app move any older host onto its binary.
    public static let version = 2

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
        public static let respondQuestion = "_native/session/respond_question"
        public static let runHidden = "_native/session/run_hidden"
        public static let closeSession = "_native/session/close"
        public static let updateQueued = "_native/queue/update"
        public static let removeQueued = "_native/queue/remove"
        public static let restoreQueued = "_native/queue/restore"
        public static let moveQueued = "_native/queue/move"
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

/// The part of `initialize`'s result that never changes across protocol versions. Clients decode
/// this first, so they can talk to a host of any version far enough to update it.
public struct FrozenHandshake: Codable, Hashable, Sendable {
    public var protocolVersion: Int
    public var hostInfo: PeerInfo

    public init(protocolVersion: Int, hostInfo: PeerInfo) {
        self.protocolVersion = protocolVersion
        self.hostInfo = hostInfo
    }
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

    public init(
        protocolVersion: Int, hostID: HostID, machineName: String, hostInfo: PeerInfo, epoch: UUID, processID: Int32,
        startedAt: Date, channel: String
    ) {
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

// MARK: - Stopping

/// Part of the frozen handshake: older hosts decode it with `stopAgents` alone.
public struct ShutdownParams: Codable, Sendable {
    /// Stop agents now, cancelling their turns ("Quit Native and Stop Agents"). Otherwise the host
    /// restarts, and launchd brings the new binary up (an update).
    public var stopAgents: Bool
    /// For a restart: exit now instead of once nothing is running ("Restart Host Now"). Interrupted
    /// turns resume on the new binary like after any interruption.
    public var immediately: Bool

    public init(stopAgents: Bool, immediately: Bool = false) {
        self.stopAgents = stopAgents
        self.immediately = immediately
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        stopAgents = try container.decode(Bool.self, forKey: .stopAgents)
        immediately = try container.decodeIfPresent(Bool.self, forKey: .immediately) ?? false
    }
}

public struct EmptyMessage: Codable, Sendable {
    public init() {}
}
