import Foundation

// Updating a host from any client (docs/releasing.md, "Remote updates"; the auth boundary is in
// docs/durability.md, "Updating a host remotely").

extension HostProtocol.Method {
    public static let updateStatus = "_native/host/update/status"
    public static let updateCheck = "_native/host/update/check"
    /// Installs what the host's own check found. Never carries a URL, version or binary.
    public static let updateInstall = "_native/host/update/install"
    /// Host → clients: the update status moved.
    public static let updateChanged = "_native/host/update/changed"
    /// The Mac app → its local host: Sparkle's status, which the host serves as its own.
    public static let updateReport = "_native/host/update/report"
    /// Host → the Mac app: check now (a device asked).
    public static let appUpdateCheck = "_native/app/update/check"
    /// Host → the Mac app: install (a device asked).
    public static let appUpdateInstall = "_native/app/update/install"
}

public struct HostUpdateStatus: Codable, Hashable, Sendable {
    /// What updates this host.
    public enum Provider: String, WireEnum {
        /// Native.app's updater, which replaces the whole bundle, host included.
        case app
        /// The host updates its own `native-host` binary.
        case standalone
        /// Nothing (development builds); `message` says why.
        case none
        case unknown
    }

    public enum State: String, WireEnum {
        case idle, checking, upToDate, available, downloading, ready, installing, failed, unavailable, unknown
    }

    /// When an install may interrupt work: once nothing is running, or now.
    public enum When: String, WireEnum {
        case idle, now, unknown
    }

    public struct Build: Codable, Hashable, Sendable {
        public var version: String
        public var build: String
        public var channel: String

        public init(version: String, build: String, channel: String) {
            self.version = version
            self.build = build
            self.channel = channel
        }
    }

    public struct Release: Codable, Hashable, Sendable {
        public var version: String
        public var build: String
        public var notes: String?
        public var releaseNotesURL: URL?
        public var date: Date?
        public var size: Int?
        public var critical: Bool

        public init(
            version: String, build: String, notes: String? = nil, releaseNotesURL: URL? = nil, date: Date? = nil,
            size: Int? = nil, critical: Bool = false
        ) {
            self.version = version
            self.build = build
            self.notes = notes
            self.releaseNotesURL = releaseNotesURL
            self.date = date
            self.size = size
            self.critical = critical
        }
    }

    public struct Rollback: Codable, Hashable, Sendable {
        public var from: String
        public var to: String
        public var at: Date

        public init(from: String, to: String, at: Date) {
            self.from = from
            self.to = to
            self.at = at
        }
    }

    public var provider: Provider
    public var current: Build
    public var state: State
    public var available: Release?
    /// 0...1 while downloading, when the size is known.
    public var progress: Double?
    /// The failure, or why updates are off, in the words the Mac shows.
    public var message: String?
    public var lastChecked: Date?
    /// An install waiting to happen.
    public var pendingInstall: When?
    /// What installing now would interrupt.
    public var workingSessions: Int
    /// Whether the client that asked may install, and there's something to install. Computed per client.
    public var canInstall: Bool
    public var lastRollback: Rollback?

    public init(
        provider: Provider, current: Build, state: State, available: Release? = nil, progress: Double? = nil,
        message: String? = nil, lastChecked: Date? = nil, pendingInstall: When? = nil, workingSessions: Int = 0,
        canInstall: Bool = false, lastRollback: Rollback? = nil
    ) {
        self.provider = provider
        self.current = current
        self.state = state
        self.available = available
        self.progress = progress
        self.message = message
        self.lastChecked = lastChecked
        self.pendingInstall = pendingInstall
        self.workingSessions = workingSessions
        self.canInstall = canInstall
        self.lastRollback = lastRollback
    }

    /// Whether there's an update to install.
    public var hasInstallableUpdate: Bool {
        available != nil && [.available, .downloading, .ready].contains(state)
    }
}

public struct HostUpdateInstallParams: Codable, Sendable {
    public var when: HostUpdateStatus.When

    public init(when: HostUpdateStatus.When) {
        self.when = when
    }
}

/// `report` (app → host) and `changed` (host → clients).
public struct HostUpdateStatusMessage: Codable, Sendable {
    public var status: HostUpdateStatus

    public init(status: HostUpdateStatus) {
        self.status = status
    }
}
