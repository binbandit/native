import Foundation
import MCP
import MCPClient
import Testing

@Suite("Switches")
struct SwitchesTests {
    let rea = ConfiguredServer(
        server: MCPServerConfig(
            name: "rea", transport: .stdio(command: "npx", arguments: ["-y", "rea-agents@6.4.0", "mcp"])),
        format: .claudeCode, scope: .user, source: URL(filePath: "/home/tester/.claude.json")
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
}
