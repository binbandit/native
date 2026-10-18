import Foundation
import Testing

@testable import ACP

@Suite struct AdapterOverridesTests {
    @Test func codexCarriesServersAndSkillsInOneDocument() throws {
        let overrides = CodexConfigOverrides(
            disabledMCPServers: ["rea"],
            disabledSkills: ["/home/me/.codex/skills/deploy", "/repo/.codex/skills/x/SKILL.md"])
        let value = try #require(overrides.environment["CODEX_CONFIG"])
        let config = try JSONDecoder().decode(JSONValue.self, from: Data(value.utf8))

        #expect(config["mcp_servers"]?["rea"]?["enabled"] == .bool(false))
        #expect(config["mcp_servers.rea.enabled"] == .bool(false))
        #expect(
            config["skills"]?["config"]
                == .array([
                    .object(["path": .string("/home/me/.codex/skills/deploy/SKILL.md"), "enabled": .bool(false)]),
                    .object(["path": .string("/repo/.codex/skills/x/SKILL.md"), "enabled": .bool(false)]),
                ]))
    }

    @Test func codexStaysQuietWithoutOverrides() {
        #expect(CodexConfigOverrides().environment.isEmpty)
        #expect(CodexConfigOverrides(disabledSkills: ["/s"]).config["mcp_servers"] == nil)
    }

    @Test func claudeCarriesServersAndSkillsInOneSettingsObject() {
        let settings = ClaudeCodeSessionSettings(deniedMCPServers: ["rea", "fs"], disabledSkills: ["deploy"]).meta
        let object = settings["claudeCode"]?["options"]?["settings"]

        #expect(
            object?["deniedMcpServers"]
                == .array([.object(["serverName": .string("fs")]), .object(["serverName": .string("rea")])]))
        #expect(object?["skillOverrides"] == .object(["deploy": .string("off")]))
        #expect(ClaudeCodeSessionSettings().meta.isEmpty)
    }
}
