import Foundation
import MCPClient
import Testing

@Suite("Managed servers")
struct ManagedServerTests {
    let inspector = ManagedServer(
        name: "inspector",
        transport: .stdio(command: "npx", arguments: ["-y", "example-inspector@2.1.0", "mcp"], environmentNames: ["INSPECTOR_LICENSE"], workingDirectory: nil)
    )
    let docs = ManagedServer(name: "docs", transport: .http(url: URL(string: "https://docs.example.com/mcp")!, headerNames: ["Authorization"]))

    private func target(agent: String = "claude-code", in directory: URL? = .app, http: Bool? = true, loads servers: [ConfiguredServer] = []) -> ManagedServerDelivery.Target {
        ManagedServerDelivery.Target(agentID: agent, directory: directory, transports: http.map { MCPTransportSupport(http: $0, sse: false) }, agentServers: servers)
    }

    private func outcomes(_ servers: [ManagedServer], for target: ManagedServerDelivery.Target) -> [String: ManagedServerDelivery.Outcome] {
        Dictionary(uniqueKeysWithValues: ManagedServerDelivery.plan(servers, for: target).map { ($0.server.name, $0.outcome) })
    }

    @Test func deliversToChosenAgentsAndProjects() {
        var scoped = docs
        scoped.agents = .only(["codex"])
        var elsewhere = inspector
        elsewhere.projects = .only(["/work/site"])
        #expect(outcomes([scoped, elsewhere], for: target()) == ["docs": .notForAgent, "inspector": .notForProject])
        #expect(outcomes([scoped, elsewhere], for: target(agent: "codex", in: URL(filePath: "/work/site/packages/web"))) == ["docs": .deliver, "inspector": .deliver])
        elsewhere.excludedProjects = ["/work/site/packages"]
        #expect(outcomes([elsewhere], for: target(agent: "codex", in: URL(filePath: "/work/site/packages/web"))) == ["inspector": .notForProject])
    }

    @Test func skipsWhatTheAgentCantConnectTo() {
        #expect(outcomes([docs], for: target(http: false)) == ["docs": .unsupportedTransport(.http)])
        // An agent that hasn't said is taken as able, as every agent today is.
        #expect(outcomes([docs], for: target(http: nil)) == ["docs": .deliver])
    }

    @Test func skipsServersTheAgentAlreadyLoads() {
        let sameCommand = ConfiguredServer(
            server: MCPServerConfig(name: "rev", transport: .stdio(command: "/opt/homebrew/bin/npx", arguments: ["-y", "example-inspector@2.1.0", "mcp"])),
            format: .claudeCode, scope: .user, source: URL(filePath: "/home/tester/.claude.json")
        )
        let sameName = ConfiguredServer(
            server: MCPServerConfig(name: "docs", transport: .http(url: URL(string: "https://other.example.com/mcp")!)),
            format: .claudeCode, scope: .user, source: URL(filePath: "/home/tester/.claude.json"), status: .disabledInProject
        )
        let plan = outcomes([inspector, docs], for: target(loads: [sameCommand, sameName]))
        #expect(plan["inspector"] == .alreadyLoaded(by: sameCommand))
        // The agent's own copy is off here, so Native's is the one that loads.
        #expect(plan["docs"] == .deliver)
    }

    @Test func disabledServersStayHome() {
        var off = docs
        off.isEnabled = false
        #expect(outcomes([off], for: target()) == ["docs": .disabled])
    }

    @Test func importingMovesValuesToSecrets() throws {
        let entry = ConfiguredServer(
            server: MCPServerConfig(name: "tracker", transport: .http(url: URL(string: "https://tracker.example.com/mcp")!, headers: ["Authorization": "Bearer ${TRACKER_TOKEN}"])),
            format: .claudeCode, scope: .local(.app), source: URL(filePath: "/home/tester/.claude.json"), resolution: .claudeCode
        )
        let (server, secrets) = try #require(ManagedServer.importing(entry, resolvedWith: ["TRACKER_TOKEN": "abc"]))
        #expect(server.name == "tracker")
        #expect(server.transport == .http(url: URL(string: "https://tracker.example.com/mcp")!, headerNames: ["Authorization"]))
        #expect(secrets.headers == ["Authorization": "Bearer abc"])
        #expect(server.origin == "Claude Code · Local")

        let encoded = String(decoding: try JSONEncoder().encode(server), as: UTF8.self)
        #expect(!encoded.contains("abc"))
        #expect(try JSONDecoder().decode(ManagedServer.self, from: Data(encoded.utf8)) == server)
        #expect(server.config(with: secrets).transport == .http(url: URL(string: "https://tracker.example.com/mcp")!, headers: ["Authorization": "Bearer abc"]))
    }

    @Test func importingPluginServersDropsThePrefix() throws {
        let entry = ConfiguredServer(server: MCPServerConfig(name: "plugin:notes:notes", transport: .stdio(command: "notes")), format: .claudeCode, scope: .plugin("notes"), source: URL(filePath: "/p"))
        #expect(try #require(ManagedServer.importing(entry)).0.name == "notes")
        let sse = ConfiguredServer(server: MCPServerConfig(name: "old", transport: .sse(url: URL(string: "https://old.example.com/sse")!)), format: .claudeCode, scope: .user, source: URL(filePath: "/p"))
        #expect(ManagedServer.importing(sse) == nil)
    }

    @Test func namesAgentsAccept() {
        #expect(ManagedServer.isValidName("linear-server_2"))
        #expect(!ManagedServer.isValidName("my server"))
        #expect(!ManagedServer.isValidName(""))
        #expect(!ManagedServer.isValidName("plugin:x"))
    }

    @Test func secretsRoundTripThroughAStore() throws {
        let store = MemorySecretStore()
        try store.setSecrets(ManagedServerSecrets(environment: ["KEY": "v"]), for: docs.id, label: "docs")
        #expect(try store.secrets(for: docs.id)?.environment == ["KEY": "v"])
        try store.setSecrets(ManagedServerSecrets(), for: docs.id, label: "docs")
        #expect(try store.secrets(for: docs.id) == nil)
    }
}

@Suite("Agent CLI commands")
struct AgentCLITests {
    let stdio = MCPServerConfig(name: "inspector", transport: .stdio(command: "npx", arguments: ["-y", "example-inspector@2.1.0", "mcp"], environment: ["LICENSE": "s3cret"]))
    let remote = MCPServerConfig(name: "docs", transport: .http(url: URL(string: "https://docs.example.com/mcp")!, headers: ["Authorization": "Bearer s3cret"]))

    @Test func claudeAddsWholeEntriesAndMasksSecrets() throws {
        let command = try AgentCLI.add(stdio, to: .claudeCode, scope: .user).get()
        #expect(command.executable == "claude")
        #expect(command.arguments == ["mcp", "add-json", "--scope", "user", "inspector", #"{"args":["-y","example-inspector@2.1.0","mcp"],"command":"npx","env":{"LICENSE":"s3cret"},"type":"stdio"}"#])
        #expect(command.displayText == #"claude mcp add-json --scope user inspector '{"args":["-y","example-inspector@2.1.0","mcp"],"command":"npx","env":{"LICENSE":"•••"},"type":"stdio"}'"#)

        let local = try AgentCLI.add(remote, to: .claudeCode, scope: .local(.app)).get()
        #expect(local.directory == "/work/app")
        #expect(local.displayText.hasPrefix("cd /work/app && claude mcp add-json --scope local docs "))
        #expect(!local.displayText.contains("s3cret"))
    }

    @Test func codexAddsWithItsFlags() throws {
        let command = try AgentCLI.add(stdio, to: .codex).get()
        #expect(command.arguments == ["mcp", "add", "inspector", "--env", "LICENSE=s3cret", "--", "npx", "-y", "example-inspector@2.1.0", "mcp"])
        #expect(command.displayText == "codex mcp add inspector --env LICENSE=••• -- npx -y example-inspector@2.1.0 mcp")
        // Codex's CLI can't set headers, so it says what to do instead.
        #expect(throws: AgentCLIUnavailable.self) { try AgentCLI.add(remote, to: .codex).get() }
        #expect(throws: AgentCLIUnavailable.self) { try AgentCLI.add(stdio, to: .cursor).get() }
    }

    @Test func removesFromTheScopeTheEntryIsIn() throws {
        let local = ConfiguredServer(server: remote, format: .claudeCode, scope: .local(.app), source: URL(filePath: "/home/tester/.claude.json"))
        #expect(try AgentCLI.remove(local).get().displayText == "cd /work/app && claude mcp remove --scope local docs")
        let codex = ConfiguredServer(server: stdio, format: .codex, scope: .user, source: URL(filePath: "/home/tester/.codex/config.toml"))
        #expect(try AgentCLI.remove(codex).get().displayText == "codex mcp remove inspector")
        let plugin = ConfiguredServer(server: stdio, format: .claudeCode, scope: .plugin("notes"), source: URL(filePath: "/p"))
        #expect(throws: AgentCLIUnavailable.self) { try AgentCLI.remove(plugin).get() }
    }

    @Test func signsInThroughTheAgent() throws {
        let entry = ConfiguredServer(server: remote, format: .codex, scope: .user, source: URL(filePath: "/c"))
        let command = try AgentCLI.signIn(entry).get()
        #expect(command.displayText == "codex mcp login docs")
        #expect(command.command(environment: [:]).timeout == .seconds(300))
        let local = ConfiguredServer(server: stdio, format: .claudeCode, scope: .user, source: URL(filePath: "/c"))
        #expect(throws: AgentCLIUnavailable.self) { try AgentCLI.signIn(local).get() }
    }

    @Test func splitsLikeAShell() {
        #expect(ShellQuoting.split(#"npx -y "my pkg" 'it''s' a\ b"#) == ["npx", "-y", "my pkg", "its", "a b"])
        #expect(ShellQuoting.split(#"echo "say \"hi\"" ''"#) == ["echo", #"say "hi""#, ""])
        #expect(ShellQuoting.split("  ") == [])
        #expect(ShellQuoting.split("echo 'open") == nil)
        let words = ["node", "it's", "a b", "plain"]
        #expect(ShellQuoting.split(ShellQuoting.commandLine(words)) == words)
    }

    @Test func quotesLikeAShell() {
        #expect(ShellQuoting.commandLine(["echo", "it's", "a b", "plain-word", ""]) == #"echo 'it'\''s' 'a b' plain-word ''"#)
    }
}
