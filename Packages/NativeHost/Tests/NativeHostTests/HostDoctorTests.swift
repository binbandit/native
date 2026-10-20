import Foundation
import NativeHostProtocol
import Testing

@testable import NativeHost

/// A machine the doctor reads from: which files are executable, what commands print, and the rest.
struct FakeDoctorMachine: HostDoctorMachine {
    var userName = "brayden"
    var homeDirectory = "/Users/brayden"
    var executables: Set<String> = []
    /// What each command line ("/opt/bin/node --version") prints; missing ones don't answer.
    var outputs: [String: HostDoctorOutput] = [:]
    var freeSpace: Int64? = 200_000_000_000
    var addresses = ["192.168.1.20"]
    var listening: Set<UInt16> = [22]

    func isExecutableFile(atPath path: String) -> Bool {
        executables.contains(path)
    }

    func run(_ executable: String, _ arguments: [String], environment: [String: String]) async -> HostDoctorOutput? {
        outputs[([executable] + arguments).joined(separator: " ")]
    }

    func availableSpace(at path: String) -> Int64? {
        freeSpace
    }

    func networkAddresses() -> [String] {
        addresses
    }

    func acceptsConnections(onPort port: UInt16) async -> Bool {
        listening.contains(port)
    }

    /// A tool at `/opt/bin/<name>` whose `--version` prints `version`.
    mutating func install(_ name: String, version: String) {
        executables.insert("/opt/bin/\(name)")
        outputs["/opt/bin/\(name) --version"] = HostDoctorOutput(status: 0, output: "\(version)\n")
    }
}

/// A platform with no checks of its own that installs tools with Homebrew.
struct FakeDoctorPlatform: HostDoctorPlatform {
    func checks(_ context: HostDoctor.Context, machine: any HostDoctorMachine) async -> [HostDoctorCheck] {
        []
    }

    func installCommand(for tool: String) -> String? {
        ["node": "brew install node", "npx": "brew install node", "gh": "brew install gh"][tool]
    }
}

@Suite("Host doctor")
struct HostDoctorTests {
    static let claude = AgentSpec(
        id: "claude-code", name: "Claude Code", command: "npx", args: ["--yes", "adapter@1"],
        resolveExecutables: ["CLAUDE_CODE_EXECUTABLE": "claude"], requires: ["claude"],
        install: "npm install -g @anthropic-ai/claude-code")
    static let codex = AgentSpec(
        id: "codex", name: "Codex", command: "npx", resolveExecutables: ["CODEX_PATH": "codex"], requires: ["codex"],
        install: "npm install -g @openai/codex")
    static let cursor = AgentSpec(
        id: "cursor", name: "Cursor", command: "cursor-agent", install: "brew install --cask cursor-cli")

    /// Node, git and a signed-in gh, as on a Mac that's ready.
    static var readyMachine: FakeDoctorMachine {
        var machine = FakeDoctorMachine()
        machine.install("node", version: "v22.11.0")
        machine.install("npx", version: "10.9.0")
        machine.install("git", version: "git version 2.50.1")
        machine.install("gh", version: "gh version 2.74.0 (2025-06-10)\nhttps://github.com/cli/cli/releases")
        machine.outputs["/opt/bin/gh auth status"] = HostDoctorOutput(
            status: 0,
            output: "github.com\n  ✓ Logged in to github.com account octocat (keyring)\n  - Token: gho_************\n")
        return machine
    }

    private func report(
        _ machine: FakeDoctorMachine, agents: [AgentSpec] = [], keepAwake: HostKeepAwakeState? = nil,
        gateway: HostDoctorGateway? = nil
    ) async -> HostDoctorReport {
        let context = HostDoctor.Context(
            machineName: "mini", environment: ["PATH": "/opt/bin:/usr/bin"], agents: agents, keepAwake: keepAwake,
            gateway: gateway, isHostRunning: true)
        return await HostDoctor(machine: machine, platform: FakeDoctorPlatform()).report(context)
    }

    private func check(_ id: String, in report: HostDoctorReport) throws -> HostDoctorCheck {
        try #require(report.checks.first { $0.id == id })
    }

    @Test(
        "Each agent's CLI is found on the login shell's PATH with its version; a missing one fails with its install command"
    )
    func agents() async throws {
        var machine = Self.readyMachine
        machine.install("claude", version: "2.1.3 (Claude Code)")
        let report = await report(machine, agents: [Self.claude, Self.codex])

        #expect(try check("agents.node", in: report).detail == "v22.11.0 at /opt/bin/node")
        let claude = try check("agents.claude-code", in: report)
        #expect(claude.status == .ok)
        #expect(claude.detail == "2.1.3 (Claude Code) at /opt/bin/claude")
        let codex = try check("agents.codex", in: report)
        #expect(codex.status == .failed)
        #expect(codex.detail == "codex isn't on your login shell's PATH")
        #expect(codex.fix?.command == "npm install -g @openai/codex")
        #expect(report.status == .failed)
    }

    @Test("A version manager's shim warning on standard error isn't a problem, nor a version")
    func shimWarnings() async throws {
        var machine = Self.readyMachine
        let warning = "mise WARN  Failed to resolve tool version list for npm:@openai/codex\n"
        machine.outputs["/opt/bin/node --version"] = HostDoctorOutput(
            status: 0, output: "v22.11.0\n", errorOutput: warning)
        machine.executables.insert("/opt/bin/codex")
        machine.outputs["/opt/bin/codex --version"] = HostDoctorOutput(status: 0, output: "", errorOutput: warning)
        let report = await report(machine, agents: [Self.codex])
        #expect(try check("agents.node", in: report).detail == "v22.11.0 at /opt/bin/node")
        let codex = try check("agents.codex", in: report)
        #expect(codex.status == .ok)
        #expect(codex.detail == "codex at /opt/bin/codex")
    }

    @Test("Node is required only when an agent runs through npx")
    func nodeOnlyWhenNeeded() async throws {
        var machine = FakeDoctorMachine()
        machine.install("cursor-agent", version: "2026.10.1")
        let withoutNode = await report(machine, agents: [Self.cursor])
        #expect(try check("agents.node", in: withoutNode).status == .warning)
        #expect(try check("agents.cursor", in: withoutNode).status == .ok)

        let needingNode = await report(machine, agents: [Self.cursor, Self.codex])
        let node = try check("agents.node", in: needingNode)
        #expect(node.status == .failed)
        #expect(node.fix?.command == "brew install node")
        let codex = try check("agents.codex", in: needingNode)
        #expect(codex.detail == "npx and codex aren't on your login shell's PATH")
        #expect(codex.fix?.setting == "Install Node.js first (see Node.js above), then the agent")
    }

    @Test("GitHub's CLI: signed in names the account; signed out says how to sign in")
    func gitHubSignIn() async throws {
        let signedIn = await report(Self.readyMachine)
        #expect(try check("tools.gh.auth", in: signedIn).detail == "Signed in to github.com as octocat")

        var machine = Self.readyMachine
        machine.outputs["/opt/bin/gh auth status"] = HostDoctorOutput(
            status: 1, output: "You are not logged into any GitHub hosts. To log in, run: gh auth login\n")
        let signedOut = try check("tools.gh.auth", in: await report(machine))
        #expect(signedOut.status == .warning)
        #expect(signedOut.fix?.command == "gh auth login")

        machine.executables.remove("/opt/bin/gh")
        let withoutGitHub = await report(machine)
        #expect(try check("tools.gh", in: withoutGitHub).status == .warning)
        #expect(withoutGitHub.checks.allSatisfy { $0.id != "tools.gh.auth" })
    }

    @Test("Free space: plenty is fine, under 20 GB warns, under 5 GB fails")
    func diskSpace() async throws {
        var machine = Self.readyMachine
        #expect(try check("system.disk", in: await report(machine)).status == .ok)
        machine.freeSpace = 12_000_000_000
        #expect(try check("system.disk", in: await report(machine)).status == .warning)
        machine.freeSpace = 3_000_000_000
        let critical = try check("system.disk", in: await report(machine))
        #expect(critical.status == .failed)
        #expect(critical.fix?.command != nil)
    }

    @Test("Addresses: the local network and Tailscale, and the port paired devices use")
    func reachability() async throws {
        var machine = Self.readyMachine
        machine.addresses = ["192.168.1.20", "100.101.102.103"]
        let gateway = HostDoctorGateway(
            isEnabled: true, isListening: true, port: 47_118, problem: nil, pairedDevices: 1)
        let network = try check("system.network", in: await report(machine, gateway: gateway))
        #expect(
            network.detail
                == "192.168.1.20 on the local network; 100.101.102.103 on Tailscale; paired devices connect on port 47118"
        )

        machine.addresses = []
        #expect(try check("system.network", in: await report(machine)).status == .failed)
    }

    @Test("Keeping awake: off says where to turn it on; a refused assertion warns")
    func keepAwake() throws {
        let off = HostKeepAwakeState(policy: KeepAwakePolicy(), status: .off, held: [])
        let offCheck = HostDoctor.keepAwakeCheck(off, now: .now)
        #expect(offCheck.status == .info)
        #expect(offCheck.fix?.setting?.contains("While Agents Work") == true)

        let working = KeepAwakeStatus.evaluate(
            KeepAwakePolicy(mode: .whileAgentsWork), workingAgents: 2, power: PowerState(), now: .now)
        let held = HostKeepAwakeState(
            policy: KeepAwakePolicy(mode: .whileAgentsWork), status: working, held: working.assertions)
        #expect(HostDoctor.keepAwakeCheck(held, now: .now).detail == "Keeping awake while 2 agents work")
        var refused = held
        refused.held = []
        #expect(HostDoctor.keepAwakeCheck(refused, now: .now).status == .warning)
        #expect(HostDoctor.keepAwakeCheck(nil, now: .now).status == .unknown)
    }

    @Test("The text report lists each problem with its fix, and ends with a count")
    func text() async throws {
        var machine = Self.readyMachine
        machine.freeSpace = 3_000_000_000
        let text = await report(machine).text
        #expect(text.hasPrefix("Native host doctor: mini"))
        #expect(text.contains("  [FAIL] Free disk space: Only 3 GB free"))
        #expect(text.contains("      Run: du -sh ~/.native/worktrees/* 2>/dev/null | sort -h"))
        #expect(text.hasSuffix("to look at."))
    }
}
