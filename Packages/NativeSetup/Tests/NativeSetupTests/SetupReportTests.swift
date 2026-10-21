import Foundation
import Testing

@testable import NativeSetup

struct SetupReportTests {
    /// A fresh development Mac: Codex running this session, Claude Code missing its CLI, Copilot
    /// signed out, no durable host, one managed key.
    private let report = SetupReport(
        native: .init(version: "0.4.0", build: "812", channel: .dev),
        agents: [
            .init(
                id: "codex", name: "Codex", state: .ready, signIn: .signedIn,
                launch: "npx --yes @agentclientprotocol/codex-acp@2.2.2", requires: ["codex"],
                version: "codex-acp 2.2.2",
                isCaller: true),
            .init(
                id: "claude-code", name: "Claude Code", state: .notInstalled, signIn: .unknown,
                launch: "npx --yes @agentclientprotocol/claude-agent-acp@0.93.0", requires: ["claude"],
                missingCommand: "claude", installCommand: "npm install -g @anthropic-ai/claude-code",
                signInCommand: "claude"),
            .init(
                id: "copilot", name: "Copilot", state: .ready, signIn: .needsSignIn, launch: "copilot --acp",
                signInCommand: "copilot login", offersSignIn: true),
        ],
        durableHost: .init(state: .off),
        pairedDevices: .init(state: .hostOff),
        organization: .init(managedKeys: ["policy.updates.enabled", "policy.agents.allowed"]),
        updates: .init(
            state: .unavailable, channel: .stable, automaticChecks: true, automaticDownloads: true,
            message: "Updates are off in development builds.")
    )

    @Test func summaryWalksTheChecksInOrder() {
        let summary = report.summary
        let headings = [
            "1. Native", "2. Agents", "3. Durable host", "4. Paired devices", "5. Organization", "6. Updates",
        ]
        let positions = headings.compactMap { summary.range(of: $0)?.lowerBound }
        #expect(positions.count == headings.count)
        #expect(positions == positions.sorted())
    }

    @Test func summarySaysWhatToDoForEachAgent() {
        let summary = report.summary
        #expect(summary.contains("2. Agents (1 of 3 ready):"))
        #expect(
            summary.contains(
                "- Codex (`codex`): ready and signed in. Reports codex-acp 2.2.2. This task runs on it."))
        #expect(
            summary.contains(
                "- Claude Code (`claude-code`): not installed: `claude` isn't on the login shell's PATH. Install with `npm install -g @anthropic-ai/claude-code`. Then Settings ▸ Agents ▸ Add an Agent ▸ Check Again."
            ))
        #expect(
            summary.contains(
                "signed out. Sign In… from the ⋯ menu on its row in Settings ▸ Agents, or run `copilot login` in a terminal."
            ))
        #expect(summary.contains("3. Durable host: off, so paired devices can't connect"))
        #expect(summary.contains("4. Paired devices: unavailable while the durable host is off"))
        #expect(summary.contains("5. Organization: manages `policy.agents.allowed`, `policy.updates.enabled`."))
        #expect(summary.contains("6. Updates: off: Updates are off in development builds."))
    }

    @Test func encodesSnakeCaseAndLeavesOutWhatIsUnknown() throws {
        let object = try #require(JSONSerialization.jsonObject(with: report.encoded()) as? [String: Any])
        #expect(
            Set(object.keys) == ["native", "agents", "durable_host", "paired_devices", "organization", "updates"])
        let agents = try #require(object["agents"] as? [[String: Any]])
        #expect(agents[0]["sign_in"] as? String == "signed_in")
        #expect(agents[0]["is_caller"] as? Bool == true)
        #expect(agents[0]["missing_command"] == nil)
        #expect(agents[1]["state"] as? String == "not_installed")
        #expect(agents[1]["missing_command"] as? String == "claude")
        let host = try #require(object["durable_host"] as? [String: Any])
        #expect(host["version_status"] as? String == "matched")
    }

    @Test func headlineDropsWhatTheAgentLogged() {
        let failure = "Codex exited.\n\nError: config at /Users/someone/.codex/config.toml: bad key"
        #expect(SetupReport.headline(of: failure) == "Codex exited.")
        #expect(SetupReport.headline(of: String(repeating: "a", count: 500)).count == 200)
    }

    /// Nothing is paired yet, so the gateway is closed; pairing opens it, so that's the step to name.
    @Test func pairedDevicesPointAtPairingBeforeTheSwitch() {
        var fresh = report
        fresh.durableHost = .init(state: .connected, version: "0.4.0")
        fresh.pairedDevices = .init(
            state: .available, paired: 0, connected: 0, acceptsConnections: false, listener: .off)
        #expect(fresh.summary.contains("To pair one: Settings ▸ Paired Devices ▸ Pair iPhone…"))
        #expect(!fresh.summary.contains("Allow paired devices to connect"))

        fresh.pairedDevices.paired = 1
        #expect(
            fresh.summary.contains("Connections are off (Settings ▸ Paired Devices ▸ Allow paired devices to connect).")
        )
    }
}
