import Foundation

/// How Native is set up on one Mac, for an agent helping the user set it up (the `native` MCP
/// server's `setup_status` tool, and the `set-up-native` skill that reads it). It holds only what
/// Settings already shows the user: no paths, secrets, tokens, environment values or transcript
/// content. Checks are listed in the order `summary` gives them.
public struct SetupReport: Encodable, Equatable, Sendable {
    public var native: Build
    public var agents: [Agent]
    public var durableHost: DurableHost
    public var pairedDevices: PairedDevices
    public var organization: Organization
    public var updates: Updates

    public init(
        native: Build, agents: [Agent], durableHost: DurableHost, pairedDevices: PairedDevices,
        organization: Organization, updates: Updates
    ) {
        self.native = native
        self.agents = agents
        self.durableHost = durableHost
        self.pairedDevices = pairedDevices
        self.organization = organization
        self.updates = updates
    }

    /// The report as JSON with snake_case keys, the way Native's other tools answer.
    public func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(self)
    }

    /// The first line of a status message, capped: an agent's failure ends with what it logged,
    /// which can hold paths and anything else it printed.
    public static func headline(of message: String) -> String {
        let line = message.split(whereSeparator: \.isNewline).first.map(String.init) ?? message
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        return trimmed.count > 200 ? String(trimmed.prefix(199)) + "…" : trimmed
    }
}

extension SetupReport {
    /// This copy of Native.
    public struct Build: Encodable, Equatable, Sendable {
        public enum Channel: String, Encodable, Sendable {
            case stable, beta, nightly
            /// Built from source; never updates itself.
            case dev
        }

        /// `1.4.0`, or `1.5.0-nightly.20261018.abc1234` for Nightly.
        public var version: String
        public var build: String
        public var channel: Channel

        public init(version: String, build: String, channel: Channel) {
            self.version = version
            self.build = build
            self.channel = channel
        }
    }

    /// One agent a plugin provides, whether or not it's installed.
    public struct Agent: Encodable, Equatable, Sendable {
        public enum State: String, Encodable, Sendable {
            /// Installed and on. An idle agent starts when a session needs it, so it counts.
            case ready
            case starting
            /// It launched and stopped, or never got going: `problem` says why.
            case stopped
            /// A command it needs isn't on the login shell's PATH: `missingCommand`.
            case notInstalled = "not_installed"
            /// Its plugin is off in Settings ▸ Agents.
            case turnedOff = "turned_off"
            /// The organization's policy doesn't allow it, or its plugin.
            case notAllowed = "not_allowed"
        }

        /// Native learns an agent is signed out only when the agent turns a session away, so until
        /// a session has started on it this launch, the answer is `unknown`.
        public enum SignIn: String, Encodable, Sendable {
            /// A session is open on it, so it accepted the sign-in it has.
            case signedIn = "signed_in"
            case needsSignIn = "needs_sign_in"
            case signingIn = "signing_in"
            case unknown
        }

        public var id: String
        public var name: String
        public var state: State
        public var signIn: SignIn
        /// How Native launches it, as Settings ▸ Agents shows it, such as
        /// `npx --yes @agentclientprotocol/codex-acp@2.2.2`.
        public var launch: String
        /// CLIs it needs on the PATH besides its command, such as the `codex` an adapter drives.
        public var requires: [String]
        /// The first command it needs that isn't on the PATH.
        public var missingCommand: String?
        /// What it reported about itself when it last started this launch, such as
        /// `codex-acp 2.2.2`: an adapter reports its own name and version.
        public var version: String?
        /// From its plugin's setup guide: a command to paste in a terminal. Native never runs it.
        public var installCommand: String?
        /// A terminal command that signs in.
        public var signInCommand: String?
        public var docs: URL?
        /// Why it stopped, without what it logged.
        public var problem: String?
        /// Whether the session asking runs on this agent.
        public var isCaller: Bool

        public init(
            id: String, name: String, state: State, signIn: SignIn, launch: String, requires: [String] = [],
            missingCommand: String? = nil, version: String? = nil, installCommand: String? = nil,
            signInCommand: String? = nil, docs: URL? = nil, problem: String? = nil, isCaller: Bool = false
        ) {
            self.id = id
            self.name = name
            self.state = state
            self.signIn = signIn
            self.launch = launch
            self.requires = requires
            self.missingCommand = missingCommand
            self.version = version
            self.installCommand = installCommand
            self.signInCommand = signInCommand
            self.docs = docs
            self.problem = problem
            self.isCaller = isCaller
        }
    }

    /// The background host that keeps agents running after Native quits (Durable Sessions), and
    /// that paired devices connect through.
    public struct DurableHost: Encodable, Equatable, Sendable {
        public enum State: String, Encodable, Sendable {
            /// Window ▸ Durable Sessions ▸ Turn On hasn't been chosen.
            case off
            case starting
            case connected
            case reconnecting
            case unreachable
            /// The host speaks another protocol version than this app.
            case incompatible
            /// Native is switched off in System Settings ▸ General ▸ Login Items & Extensions.
            case needsApproval = "needs_approval"
            case failed
        }

        public enum VersionStatus: String, Encodable, Sendable {
            case matched
            /// The host is older and switches to this app's build once its tasks finish.
            case restartPending = "restart_pending"
            /// The host is newer: this copy of Native is out of date.
            case appOutdated = "app_outdated"
        }

        public var state: State
        /// The host's Native version, once connected.
        public var version: String?
        public var versionStatus: VersionStatus
        public var problem: String?

        public init(
            state: State, version: String? = nil, versionStatus: VersionStatus = .matched, problem: String? = nil
        ) {
            self.state = state
            self.version = version
            self.versionStatus = versionStatus
            self.problem = problem
        }
    }

    /// The iPhone companion and other devices paired with this Mac's host (Settings ▸ Paired Devices).
    public struct PairedDevices: Encodable, Equatable, Sendable {
        public enum State: String, Encodable, Sendable {
            case available
            /// The gateway lives in the durable host, which is off.
            case hostOff = "host_off"
            /// The host is on but its gateway didn't answer: it's starting, or stopped.
            case waitingForHost = "waiting_for_host"
        }

        /// Whether the gateway is listening on the network for devices.
        public enum Listener: String, Encodable, Sendable {
            case off, starting, listening, failed, unknown
        }

        public var state: State
        /// Paired devices, not counting removed ones.
        public var paired: Int?
        public var connected: Int?
        /// Settings ▸ Paired Devices ▸ Allow paired devices to connect.
        public var acceptsConnections: Bool?
        public var listener: Listener?
        /// A Pair iPhone code is showing on the Mac right now.
        public var pairingOpen: Bool
        /// `policy.companion.enabled`, as the app and the host read it.
        public var allowedByOrganization: Bool
        public var problem: String?

        public init(
            state: State, paired: Int? = nil, connected: Int? = nil, acceptsConnections: Bool? = nil,
            listener: Listener? = nil, pairingOpen: Bool = false, allowedByOrganization: Bool = true,
            problem: String? = nil
        ) {
            self.state = state
            self.paired = paired
            self.connected = connected
            self.acceptsConnections = acceptsConnections
            self.listener = listener
            self.pairingOpen = pairingOpen
            self.allowedByOrganization = allowedByOrganization
            self.problem = problem
        }
    }

    /// Which settings the organization's configuration profile manages, by key only.
    public struct Organization: Encodable, Equatable, Sendable {
        /// `policy.*` keys in effect, sorted.
        public var managedKeys: [String]
        /// Keys whose values Native couldn't use and ignored, sorted.
        public var ignoredKeys: [String]

        public init(managedKeys: [String] = [], ignoredKeys: [String] = []) {
            self.managedKeys = managedKeys.sorted()
            self.ignoredKeys = Array(Set(ignoredKeys)).sorted()
        }
    }

    /// Native's own updates (Settings ▸ Updates).
    public struct Updates: Encodable, Equatable, Sendable {
        public enum State: String, Encodable, Sendable {
            case idle, checking
            case upToDate = "up_to_date"
            case available, downloading, ready, installing, failed
            /// This build can't update itself: `message` says why.
            case unavailable
        }

        public enum Channel: String, Encodable, Sendable {
            case stable, beta, nightly
        }

        public var state: State
        public var channel: Channel
        public var availableVersion: String?
        public var automaticChecks: Bool
        public var automaticDownloads: Bool
        public var lastChecked: Date?
        /// The failure, or why updates are off, in the words the Mac shows.
        public var message: String?

        public init(
            state: State, channel: Channel, availableVersion: String? = nil, automaticChecks: Bool,
            automaticDownloads: Bool, lastChecked: Date? = nil, message: String? = nil
        ) {
            self.state = state
            self.channel = channel
            self.availableVersion = availableVersion
            self.automaticChecks = automaticChecks
            self.automaticDownloads = automaticDownloads
            self.lastChecked = lastChecked
            self.message = message
        }
    }
}
