import Foundation
import MCP
import MCPClient
import Testing

@Suite("Switches and session overrides")
struct SessionOverridesTests {
    let rea = ConfiguredServer(
        server: MCPServerConfig(
            name: "rea", transport: .stdio(command: "npx", arguments: ["-y", "rea-agents@6.4.0", "mcp"])),
        format: .claudeCode, scope: .user, source: URL(filePath: "/home/tester/.claude.json")
    )
    let docs = ConfiguredServer(
        server: MCPServerConfig(name: "docs", transport: .http(url: URL(string: "https://docs.example.com/mcp")!)),
        format: .codex, scope: .user, source: URL(filePath: "/home/tester/.codex/config.toml")
    )

    @Test func projectsOverrideTheGlobalSwitch() throws {
        var switches = MCPServerSwitches()
        let key = rea.server.endpoint.key
        #expect(switches.mode(of: key, in: .app) == .on)
        switches.set(.off, for: key, in: nil)
        switches.set(.on, for: key, in: .app)
        #expect(switches.mode(of: key, in: URL(filePath: "/work/app/packages/web")) == .on)
        #expect(switches.mode(of: key, in: .site) == .off)
        #expect(switches.globallyOff == [key])
        switches.set(nil, for: key, in: .app)
        #expect(switches.mode(of: key, in: .app) == .off)
        #expect(!switches.hasProjectOverrides(for: key))
        #expect(try JSONDecoder().decode(MCPServerSwitches.self, from: JSONEncoder().encode(switches)) == switches)
    }

    @Test func sameServerSameSwitchWhateverItsName() {
        let renamed = MCPServerConfig(
            name: "reverse",
            transport: .stdio(command: "/opt/homebrew/bin/npx", arguments: ["-y", "rea-agents@6.4.0", "mcp"]))
        #expect(renamed.endpoint.key == rea.server.endpoint.key)
        #expect(rea.server.endpoint.key == "command:npx -y rea-agents@6.4.0 mcp")
    }

    @Test func claudeDeniesPerSession() throws {
        let overrides = MCPSessionOverrides.disabling([rea], offEverywhere: [], for: .claudeCode)
        let denied = overrides.sessionMeta["claudeCode"]?["options"]?["settings"]?["deniedMcpServers"]
        #expect(denied == [["serverName": "rea"]])
        #expect(overrides.launchConfiguration.isEmpty)
        #expect(overrides.limitations.isEmpty)
    }

    @Test func codexTurnsServersOffForItsProcess() {
        let overrides = MCPSessionOverrides.disabling([docs], offEverywhere: [docs], for: .codex)
        #expect(overrides.launchEnvironment == ["CODEX_CONFIG": #"{"mcp_servers":{"docs":{"enabled":false}}}"#])
        #expect(overrides.sessionMeta.isEmpty)
        // Off in one project only: Codex can't, and says so.
        let projectOnly = MCPSessionOverrides.disabling([docs], offEverywhere: [], for: .codex)
        #expect(projectOnly.launchConfiguration.isEmpty)
        #expect(projectOnly.limitations == ["Codex can't leave docs out of one project's sessions, only all of them."])
    }

    @Test func cursorCantBeAsked() {
        let overrides = MCPSessionOverrides.disabling([rea], offEverywhere: [rea], for: .cursor)
        #expect(overrides.isEmpty)
        #expect(overrides.limitations.count == 1)
    }

    @Test func overridesFromSeveralFeaturesMerge() {
        let mcp = MCPSessionOverrides.disabling([rea], offEverywhere: [], for: .claudeCode)
        let skills = AgentSessionOverrides(sessionMeta: [
            "claudeCode": ["options": ["settings": ["deniedMcpServers": [["serverName": "other"]]], "skills": ["a"]]]
        ])
        let merged = mcp.merging(skills)
        #expect(
            merged.sessionMeta["claudeCode"]?["options"]?["settings"]?["deniedMcpServers"] == [
                ["serverName": "rea"], ["serverName": "other"],
            ])
        #expect(merged.sessionMeta["claudeCode"]?["options"]?["skills"] == ["a"])
    }
}
