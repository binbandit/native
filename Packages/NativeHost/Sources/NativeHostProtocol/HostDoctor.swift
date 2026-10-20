import Foundation

// The host doctor (docs/droids.md): read-only checks of what a host needs to run agents on its own,
// each with the exact command or setting that fixes it. It never installs or changes anything.

extension HostProtocol.Method {
    /// → `HostDoctorReport`.
    public static let doctor = "_native/host/doctor"
}

public struct HostDoctorReport: Codable, Hashable, Sendable {
    public var machineName: String
    public var checkedAt: Date
    /// False when no host answered and the machine was checked without one (`Native Host doctor`
    /// over SSH while the host is down): the host's own checks then say so.
    public var isHostRunning: Bool
    public var checks: [HostDoctorCheck]

    public init(machineName: String, checkedAt: Date, isHostRunning: Bool, checks: [HostDoctorCheck]) {
        self.machineName = machineName
        self.checkedAt = checkedAt
        self.isHostRunning = isHostRunning
        self.checks = checks
    }

    /// The worst status among the checks.
    public var status: HostDoctorCheck.Status {
        checks.map(\.status).max() ?? .ok
    }

    /// The checks of each group, in the groups' order, leaving out empty ones.
    public var groups: [(group: HostDoctorCheck.Group, checks: [HostDoctorCheck])] {
        HostDoctorCheck.Group.ordered.compactMap { group in
            let checks = checks.filter { $0.group == group }
            return checks.isEmpty ? nil : (group, checks)
        }
    }

    /// The report as plain text: what `doctor` prints over SSH and Copy as Text copies.
    public var text: String {
        var lines = ["Native host doctor: \(machineName)"]
        if !isHostRunning {
            lines.append("Native's background host isn't running, so this Mac was checked without it.")
        }
        for (group, checks) in groups {
            lines.append("")
            lines.append(group.title)
            for check in checks {
                lines.append("  [\(check.status.label)] \(check.title): \(check.detail)")
                if let setting = check.fix?.setting {
                    lines.append("      Fix: \(setting)")
                }
                if let command = check.fix?.command {
                    lines.append("      Run: \(command)")
                }
            }
        }
        let problems = checks.count { $0.status >= .warning }
        lines.append("")
        lines.append(problems == 0 ? "Everything looks ready." : "\(problems) to look at.")
        return lines.joined(separator: "\n")
    }
}

public struct HostDoctorCheck: Codable, Hashable, Sendable, Identifiable {
    /// Ordered from fine to worst, so the worst of a report is its `max()`.
    public enum Status: String, WireEnum, Comparable {
        case ok
        /// Worth knowing, nothing to do.
        case info
        /// Works, but not the way a droid should (sleeps, won't log in by itself).
        case warning
        /// Missing or broken: agents can't run as they should until it's fixed.
        case failed
        case unknown

        private var rank: Int {
            switch self {
            case .ok: 0
            case .info: 1
            case .unknown: 2
            case .warning: 3
            case .failed: 4
            }
        }

        public static func < (lhs: Self, rhs: Self) -> Bool {
            lhs.rank < rhs.rank
        }

        /// For plain text, where there are no colors.
        public var label: String {
            switch self {
            case .ok: "ok"
            case .info: "info"
            case .warning: "warn"
            case .failed: "FAIL"
            case .unknown: "?"
            }
        }
    }

    public enum Group: String, WireEnum {
        /// The background host itself: how it starts, keeping awake.
        case host
        /// Node and each agent's CLI on the login shell's PATH.
        case agents
        /// Git and GitHub's CLI.
        case tools
        /// Disk space and how the machine can be reached.
        case system
        /// What a machine that runs without anyone at it needs: logging in, staying up.
        case unattended
        case unknown

        public static let ordered: [Group] = [.host, .agents, .tools, .system, .unattended, .unknown]

        public var title: String {
            switch self {
            case .host: "Background host"
            case .agents: "Agents"
            case .tools: "Git and GitHub"
            case .system: "Disk and network"
            case .unattended: "Running unattended"
            case .unknown: "Other"
            }
        }
    }

    /// Stable, so a client can key on it: `host.loginItem`, `agents.node`, `agents.<agent id>`,
    /// `tools.gh.auth`, `unattended.sleep`, ….
    public var id: String
    public var group: Group
    public var title: String
    public var status: Status
    /// What was found: a version and path, a setting's value, an amount of space.
    public var detail: String
    public var fix: HostDoctorFix?

    public init(
        id: String, group: Group, title: String, status: Status, detail: String, fix: HostDoctorFix? = nil
    ) {
        self.id = id
        self.group = group
        self.title = title
        self.status = status
        self.detail = detail
        self.fix = fix
    }
}

/// How to fix a check, for the user to do: the doctor never does it.
public struct HostDoctorFix: Codable, Hashable, Sendable {
    /// Where to change it, as the host's settings label it ("System Settings ▸ Energy ▸ …").
    public var setting: String?
    /// A command to run in a terminal on the host (over SSH for a droid), exactly as written.
    public var command: String?

    public init(setting: String? = nil, command: String? = nil) {
        self.setting = setting
        self.command = command
    }
}

/// The paired-device gateway as the doctor reports it: whether it listens, and on which port.
public struct HostDoctorGateway: Codable, Hashable, Sendable {
    public var isEnabled: Bool
    public var isListening: Bool
    public var port: UInt16?
    public var problem: String?
    public var pairedDevices: Int

    public init(isEnabled: Bool, isListening: Bool, port: UInt16?, problem: String?, pairedDevices: Int) {
        self.isEnabled = isEnabled
        self.isListening = isListening
        self.port = port
        self.problem = problem
        self.pairedDevices = pairedDevices
    }
}
