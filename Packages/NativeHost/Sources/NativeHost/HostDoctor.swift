import Foundation
import NativeHostProtocol

/// What the doctor reads from the machine it checks. The real one runs commands and asks the system
/// (`NativeHostMac.HostDoctorMacMachine`); tests give a fake machine. Reads only: nothing here
/// installs or changes anything.
public protocol HostDoctorMachine: Sendable {
    var userName: String { get }
    var homeDirectory: String { get }
    func isExecutableFile(atPath path: String) -> Bool
    /// Runs `executable` (an absolute path) to completion with `environment`; nil if it couldn't
    /// start or didn't finish in time.
    func run(_ executable: String, _ arguments: [String], environment: [String: String]) async -> HostDoctorOutput?
    /// Bytes free on the volume holding `path`, counting what the system can make available.
    func availableSpace(at path: String) -> Int64?
    /// The machine's IPv4 addresses, without loopback.
    func networkAddresses() -> [String]
    /// Whether something on this machine accepts TCP connections on `port`.
    func acceptsConnections(onPort port: UInt16) async -> Bool
}

/// A command's exit status and what it printed.
public struct HostDoctorOutput: Hashable, Sendable {
    public var status: Int32
    /// Standard output.
    public var output: String
    /// Standard error, kept apart: version managers' shims (mise, asdf) warn there on every call,
    /// which says nothing about the tool.
    public var errorOutput: String

    public init(status: Int32, output: String, errorOutput: String = "") {
        self.status = status
        self.output = output
        self.errorOutput = errorOutput
    }

    /// Standard output's first line with anything on it, trimmed: where `--version` puts the version.
    public var firstLine: String? {
        output.split(whereSeparator: \.isNewline).lazy
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .first { !$0.isEmpty }
    }
}

/// The checks only a platform knows how to make (how the host starts at login, whether the machine
/// logs in and stays up by itself), and the commands it installs missing tools with.
public protocol HostDoctorPlatform: Sendable {
    func checks(_ context: HostDoctor.Context, machine: any HostDoctorMachine) async -> [HostDoctorCheck]
    /// The command that installs a missing tool (`node`, `git`, `gh`), if the platform has one.
    func installCommand(for tool: String) -> String?
}

/// Read-only checks of what a host needs to run agents on its own (docs/droids.md), each with the
/// exact command or setting that fixes it. The checks any platform can make are here and in
/// `HostDoctor+Checks.swift`; the rest come from `platform`.
public struct HostDoctor: Sendable {
    /// What the host knows that the machine doesn't say.
    public struct Context: Sendable {
        public var machineName: String
        /// The login shell's environment, which agents get: its PATH is where commands are found.
        public var environment: [String: String]
        /// The agents the host runs, from its catalog; empty when no host answered.
        public var agents: [AgentSpec]
        /// Nil when no host is running.
        public var keepAwake: HostKeepAwakeState?
        public var gateway: HostDoctorGateway?
        public var isHostRunning: Bool
        /// How the host updates; nil when no host answered.
        public var updates: HostUpdateStatus?

        public init(
            machineName: String, environment: [String: String], agents: [AgentSpec], keepAwake: HostKeepAwakeState?,
            gateway: HostDoctorGateway? = nil, isHostRunning: Bool, updates: HostUpdateStatus? = nil
        ) {
            self.machineName = machineName
            self.environment = environment
            self.agents = agents
            self.keepAwake = keepAwake
            self.gateway = gateway
            self.isHostRunning = isHostRunning
            self.updates = updates
        }
    }

    public var machine: any HostDoctorMachine
    public var platform: (any HostDoctorPlatform)?

    public init(machine: any HostDoctorMachine, platform: (any HostDoctorPlatform)?) {
        self.machine = machine
        self.platform = platform
    }

    /// Runs every check, the slow ones (versions, `gh auth status`) side by side. Off the host's
    /// actor, so sessions carry on meanwhile.
    @concurrent
    public func report(_ context: Context, now: Date = .now) async -> HostDoctorReport {
        async let platformChecks = platform?.checks(context, machine: machine) ?? []
        async let agentChecks = agentChecks(context)
        async let toolChecks = toolChecks(context)
        async let systemChecks = systemChecks(context)
        // The platform's host checks lead their group; its others follow the portable ones.
        let platform = await platformChecks
        let checks =
            platform.filter { $0.group == .host } + [Self.keepAwakeCheck(context.keepAwake, now: now)]
            + (context.updates.map { [Self.updatesCheck($0)] } ?? []) + (await agentChecks) + (await toolChecks)
            + (await systemChecks) + platform.filter { $0.group != .host }
        return HostDoctorReport(
            machineName: context.machineName, checkedAt: now, isHostRunning: context.isHostRunning, checks: checks)
    }
}
