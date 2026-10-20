import Foundation
import NativeHostProtocol

// The checks any platform can make: Node and each agent's CLI, Git and GitHub's CLI, disk space,
// the network, and keeping awake.
extension HostDoctor {
    /// Below these, agents start failing to write files and worktrees, or soon will.
    static let lowDiskSpace: Int64 = 20_000_000_000
    static let criticalDiskSpace: Int64 = 5_000_000_000

    // MARK: - Agents

    func agentChecks(_ context: Context) async -> [HostDoctorCheck] {
        // With no catalog to go by (no host answered), assume agents need Node, as most do.
        let needsNode = context.agents.isEmpty || context.agents.contains { Self.commands(of: $0).contains("npx") }
        async let node = toolCheck(
            id: "agents.node", group: .agents, title: "Node.js", command: "node",
            purpose: "agents' adapters run on it", isRequired: needsNode, context)
        async let npx = toolCheck(
            id: "agents.npx", group: .agents, title: "npx", command: "npx",
            purpose: "Native starts agents' adapters with it", isRequired: needsNode, context)
        let agents = await withTaskGroup(of: (Int, HostDoctorCheck).self) { group in
            for (index, agent) in context.agents.enumerated() {
                group.addTask { (index, await agentCheck(agent, context)) }
            }
            var checks: [(Int, HostDoctorCheck)] = []
            for await check in group {
                checks.append(check)
            }
            return checks.sorted { $0.0 < $1.0 }.map(\.1)
        }
        return await [node, npx] + agents
    }

    /// Whether every command the agent needs is on the PATH, and its CLI's version.
    func agentCheck(_ agent: AgentSpec, _ context: Context) async -> HostDoctorCheck {
        let id = "agents.\(agent.id)"
        let cli = Self.cli(of: agent)
        let missing = Self.commands(of: agent).filter { locate($0, in: context.environment) == nil }
        guard missing.isEmpty else {
            let needsNode = missing.contains { $0 == "npx" || $0 == "node" }
            let fix: HostDoctorFix =
                if missing.contains(cli), let install = agent.install {
                    HostDoctorFix(
                        setting: needsNode ? "Install Node.js first (see Node.js above), then the agent" : nil,
                        command: install)
                } else if needsNode {
                    HostDoctorFix(
                        setting: "Install Node.js (see Node.js above)", command: platform?.installCommand(for: "node"))
                } else {
                    HostDoctorFix(
                        setting: "Install \(Self.list(missing)) so your login shell finds it",
                        command: "\"$SHELL\" -lc 'command -v \(missing[0])'")
                }
            return HostDoctorCheck(
                id: id, group: .agents, title: agent.name, status: .failed,
                detail: "\(Self.list(missing)) \(missing.count == 1 ? "isn't" : "aren't") on your login shell's PATH",
                fix: fix)
        }
        let path = locate(cli, in: context.environment) ?? cli
        let version = await version(at: path, context.environment)
        return HostDoctorCheck(
            id: id, group: .agents, title: agent.name, status: .ok, detail: "\(version ?? cli) at \(path)")
    }

    /// The command, then what it requires and the CLIs it resolves, once each.
    static func commands(of agent: AgentSpec) -> [String] {
        var commands: [String] = []
        let resolved = agent.resolveExecutables.keys.sorted().compactMap { agent.resolveExecutables[$0] }
        for command in [agent.command] + agent.requires + resolved where !commands.contains(command) {
            commands.append(command)
        }
        return commands
    }

    /// The agent's own CLI, whose version says which agent this is: what an adapter drives, or the
    /// command itself.
    static func cli(of agent: AgentSpec) -> String {
        let resolved = agent.resolveExecutables.keys.sorted().compactMap { agent.resolveExecutables[$0] }
        return (agent.requires + resolved).first { $0 != agent.command } ?? agent.command
    }

    // MARK: - Tools

    func toolChecks(_ context: Context) async -> [HostDoctorCheck] {
        async let git = toolCheck(
            id: "tools.git", group: .tools, title: "Git", command: "git",
            purpose: "Native makes each task's worktree with it", isRequired: true, context)
        async let gh = toolCheck(
            id: "tools.gh", group: .tools, title: "GitHub CLI", command: "gh",
            purpose: "Native opens pull requests with it", isRequired: false, context)
        async let auth = gitHubSignInCheck(context)
        return await [git, gh] + [auth].compactMap(\.self)
    }

    /// A tool on the login shell's PATH, with its version. A missing tool fails when something
    /// needs it, and only warns otherwise.
    func toolCheck(
        id: String, group: HostDoctorCheck.Group, title: String, command: String, purpose: String, isRequired: Bool,
        _ context: Context
    ) async -> HostDoctorCheck {
        guard let path = locate(command, in: context.environment) else {
            return HostDoctorCheck(
                id: id, group: group, title: title, status: isRequired ? .failed : .warning,
                detail: "`\(command)` isn't on your login shell's PATH; \(purpose)",
                fix: HostDoctorFix(
                    setting: "Install it where your login shell finds it",
                    command: platform?.installCommand(for: command)))
        }
        let version = await version(at: path, context.environment)
        return HostDoctorCheck(
            id: id, group: group, title: title, status: .ok, detail: "\(version ?? command) at \(path)")
    }

    /// Whether `gh` is signed in, from `gh auth status` (which masks the token). Nil without `gh`.
    func gitHubSignInCheck(_ context: Context) async -> HostDoctorCheck? {
        guard let gh = locate("gh", in: context.environment) else { return nil }
        let id = "tools.gh.auth"
        let title = "GitHub sign-in"
        let fix = HostDoctorFix(
            setting: "Sign in over SSH; it shows a code to enter in a browser", command: "gh auth login")
        guard let result = await machine.run(gh, ["auth", "status"], environment: context.environment) else {
            return HostDoctorCheck(
                id: id, group: .tools, title: title, status: .unknown, detail: "`gh auth status` didn't answer")
        }
        // Older versions of gh print this to standard error.
        let output = result.output + result.errorOutput
        if result.status == 0 {
            let account = Self.gitHubAccounts(in: output).first
            return HostDoctorCheck(
                id: id, group: .tools, title: title, status: .ok,
                detail: account.map { "Signed in to \($0.host) as \($0.login)" } ?? "Signed in")
        }
        let lines = output.split(whereSeparator: \.isNewline).map { $0.trimmingCharacters(in: .whitespaces) }
        let detail =
            output.localizedCaseInsensitiveContains("not logged in")
            ? "Not signed in; Native can't open pull requests"
            : lines.first {
                $0.localizedCaseInsensitiveContains("failed") || $0.localizedCaseInsensitiveContains("invalid")
            }
                ?? lines.first { !$0.isEmpty } ?? "`gh auth status` failed"
        return HostDoctorCheck(id: id, group: .tools, title: title, status: .warning, detail: detail, fix: fix)
    }

    /// "Logged in to github.com account octocat (keyring)", or "… as octocat" from older versions.
    static func gitHubAccounts(in output: String) -> [(host: String, login: String)] {
        output.split(whereSeparator: \.isNewline).compactMap { line in
            let words = line.split(separator: " ").map(String.init)
            guard let index = words.firstIndex(of: "Logged"), words.count > index + 5,
                words[index + 1] == "in", words[index + 2] == "to", ["account", "as"].contains(words[index + 4])
            else { return nil }
            return (words[index + 3], words[index + 5])
        }
    }

    // MARK: - Disk and network

    func systemChecks(_ context: Context) async -> [HostDoctorCheck] {
        [diskCheck(), networkCheck(context.gateway)]
    }

    func diskCheck() -> HostDoctorCheck {
        let id = "system.disk"
        let title = "Free disk space"
        guard let free = machine.availableSpace(at: machine.homeDirectory) else {
            return HostDoctorCheck(
                id: id, group: .system, title: title, status: .unknown, detail: "Couldn't read the free space")
        }
        let amount = ByteCountFormatter.string(fromByteCount: free, countStyle: .file)
        guard free < Self.lowDiskSpace else {
            return HostDoctorCheck(id: id, group: .system, title: title, status: .ok, detail: "\(amount) free")
        }
        let isCritical = free < Self.criticalDiskSpace
        return HostDoctorCheck(
            id: id, group: .system, title: title, status: isCritical ? .failed : .warning,
            detail: isCritical
                ? "Only \(amount) free: agents will fail to write files and make worktrees"
                : "Only \(amount) free: worktrees and dependencies fill it quickly",
            fix: HostDoctorFix(
                setting: "Remove the worktrees of finished tasks (Clean Up Merged in Native) and empty the Trash",
                command: "du -sh ~/.native/worktrees/* 2>/dev/null | sort -h"))
    }

    /// The addresses other devices reach the host on: SSH for another Mac, the gateway's port for
    /// paired devices.
    func networkCheck(_ gateway: HostDoctorGateway?) -> HostDoctorCheck {
        let id = "system.network"
        let title = "Reachable at"
        let addresses = machine.networkAddresses()
        guard !addresses.isEmpty else {
            return HostDoctorCheck(
                id: id, group: .system, title: title, status: .failed,
                detail: "No network address: other devices can't reach this machine",
                fix: HostDoctorFix(setting: "Connect it to a network; Ethernet is the steadiest for a droid"))
        }
        let tailnet = addresses.filter(Self.isTailnet)
        let local = addresses.filter { !Self.isTailnet($0) }
        var parts: [String] = []
        if !local.isEmpty { parts.append("\(local.joined(separator: ", ")) on the local network") }
        if !tailnet.isEmpty { parts.append("\(tailnet.joined(separator: ", ")) on Tailscale") }
        var status = HostDoctorCheck.Status.ok
        if let gateway {
            if gateway.isListening, let port = gateway.port {
                parts.append("paired devices connect on port \(port)")
            } else if let problem = gateway.problem {
                status = .warning
                parts.append("paired devices can't connect: \(problem)")
            } else if !gateway.isEnabled {
                parts.append("paired devices are turned off")
            } else if gateway.pairedDevices == 0 {
                parts.append("nothing listens for paired devices until one is paired")
            }
        }
        return HostDoctorCheck(
            id: id, group: .system, title: title, status: status, detail: parts.joined(separator: "; "))
    }

    /// 100.64.0.0/10, the carrier-grade NAT range Tailscale assigns from.
    static func isTailnet(_ address: String) -> Bool {
        let parts = address.split(separator: ".").compactMap { Int($0) }
        return parts.count == 4 && parts[0] == 100 && (64...127).contains(parts[1])
    }

    // MARK: - Keeping awake

    static func keepAwakeCheck(_ state: HostKeepAwakeState?, now: Date) -> HostDoctorCheck {
        let id = "host.keepAwake"
        let title = "Keep awake"
        func check(_ status: HostDoctorCheck.Status, _ detail: String, fix: HostDoctorFix? = nil) -> HostDoctorCheck {
            HostDoctorCheck(id: id, group: .host, title: title, status: status, detail: detail, fix: fix)
        }
        guard let state else {
            return check(.unknown, "The host isn't running, so nothing keeps this machine awake while agents work")
        }
        guard state.isSupported else { return check(.info, "This host can't keep its machine awake") }
        guard state.status.assertions.isSubset(of: state.held) else {
            return check(
                .warning, "The system didn't let Native keep this machine awake",
                fix: HostDoctorFix(setting: "See what holds or blocks sleep", command: "pmset -g assertions"))
        }
        switch state.status.reason {
        case .off:
            return check(
                .info, "Off: the machine sleeps on its usual schedule, also while agents work",
                fix: HostDoctorFix(setting: "In Native: Settings ▸ Keep Awake ▸ Keep Mac awake ▸ While Agents Work"))
        case .waitingForAgents:
            return check(.ok, "While agents work; none is working now")
        case .agentsWorking:
            let count = state.status.workingAgents
            return check(
                .ok, count == 1 ? "Keeping awake while an agent works" : "Keeping awake while \(count) agents work")
        case .alwaysOn:
            return check(.ok, "On: keeping awake all the time")
        case .timer:
            let until = state.status.until.map { " until \($0.formatted(date: .omitted, time: .shortened))" } ?? ""
            return check(.ok, "Keeping awake\(until)")
        case .pausedOnBattery:
            return check(.info, "Paused on battery power")
        case .pausedLowBattery:
            return check(.info, "Paused below 10% battery")
        case .unknown:
            return check(.unknown, "This host keeps awake in a way this client doesn't know")
        }
    }

    // MARK: - Updates

    /// How the host gets its updates: with Native.app, by itself, or not on this host yet.
    static func updatesCheck(_ status: HostUpdateStatus) -> HostDoctorCheck {
        func check(_ result: HostDoctorCheck.Status, _ detail: String) -> HostDoctorCheck {
            HostDoctorCheck(id: "host.updates", group: .host, title: "Updates", status: result, detail: detail)
        }
        let current = "\(status.current.version) (\(status.current.channel))"
        if let rollback = status.lastRollback {
            return check(.warning, "Native Host \(rollback.from) didn't start, so the host went back to \(rollback.to)")
        }
        switch status.provider {
        case .app: return check(.ok, "Updates with Native, now \(current)")
        case .standalone: return check(.ok, "Updates itself, now \(current)")
        case .none, .unknown: return check(.info, status.message ?? "Updates aren't available on this host yet")
        }
    }

    // MARK: - Reading the machine

    /// Finds `command` as a login shell would: an absolute path as is, a name on the PATH.
    func locate(_ command: String, in environment: [String: String]) -> String? {
        if command.contains("/") {
            return machine.isExecutableFile(atPath: command) ? command : nil
        }
        for directory in (environment["PATH"] ?? "").split(separator: ":") where !directory.isEmpty {
            let candidate = "\(directory)/\(command)"
            if machine.isExecutableFile(atPath: candidate) { return candidate }
        }
        return nil
    }

    func version(at path: String, _ environment: [String: String]) async -> String? {
        guard let result = await machine.run(path, ["--version"], environment: environment), result.status == 0 else {
            return nil
        }
        return result.firstLine
    }

    /// "claude", "npx and claude", "a, b and c".
    static func list(_ names: [String]) -> String {
        guard let last = names.last, names.count > 1 else { return names.first ?? "" }
        return names.dropLast().joined(separator: ", ") + " and " + last
    }
}
