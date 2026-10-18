import Foundation
import MCP
import MCPClient
import NativePolicy
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
        switches.set(.scripted, for: key, in: .site)
        #expect(switches.mode(of: key, in: .site) == .scripted)
        #expect(!switches.mode(of: key, in: .site).reachesAgents)
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

    @Test func policyAndSwitchesKeepServersOut() throws {
        let fs = ConfiguredServer(
            server: MCPServerConfig(name: "fs", transport: .stdio(command: "npx", arguments: ["-y", "fs-server"])),
            format: .claudeCode, scope: .user, source: URL(filePath: "/home/tester/.claude.json"))
        var switches = MCPServerSwitches()
        switches.set(.scripted, for: fs.server.endpoint.key, in: .app)
        var policy = NativePolicy.MCP()
        policy.blocked = [try #require(MCPServerPattern("command:npx -y rea-agents*"))]

        let inApp = switches.exclusions(of: [rea, fs], in: .app, policy: policy)
        #expect(inApp.map(\.server.name) == ["rea", "fs"])
        #expect(inApp.map(\.everywhere) == [true, false])
        // At launch only what's kept out everywhere applies.
        #expect(switches.exclusions(of: [rea, fs], in: nil, policy: policy).map(\.server.name) == ["rea"])

        // An allowlist keeps out everything it doesn't name.
        policy = NativePolicy.MCP()
        policy.allowed = [try #require(MCPServerPattern("fs"))]
        #expect(switches.exclusions(of: [rea, fs], in: .site, policy: policy).map(\.server.name) == ["rea"])
        #expect(switches.exclusions(of: [rea, fs], in: .site, policy: NativePolicy.MCP()).isEmpty)
    }
}
