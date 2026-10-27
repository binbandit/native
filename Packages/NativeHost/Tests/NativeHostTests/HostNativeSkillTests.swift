#if canImport(Network) && canImport(CryptoKit)
import ACP
import Foundation
import NativeHostProtocol
import NativeOrchestration
import Testing

@testable import NativeHost

@Suite("Native skill delivery", .serialized)
@HostActor
struct HostNativeSkillTests {
    private func host(_ root: URL) throws -> HostCore {
        var configuration = HostCore.Configuration(
            location: HostLocation(directory: root, isDevelopment: true),
            hostInfo: PeerInfo(name: "fixture", version: "1", build: "1"), machineName: "fixture", bootTime: nil,
            environment: { [:] }, exit: { _ in })
        configuration.actionExecutable = URL(filePath: "/fixture/Native Host")
        return try HostCore(configuration: configuration)
    }

    @Test("A skill removes MCP by default; explicit opt-in and unsupported agents retain it")
    func delivery() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "host-skill-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let core = try host(root)
        let spec = AgentSpec(id: "fixture", name: "Fixture", command: "/fixture", nativeSkill: .claudeCode)
        try core.syncAgents([spec])
        let environment = core.tasks.prepareSkill(for: spec, environment: [:])
        #expect(environment[NativeActionCLI.executableVariable] == "/fixture/Native Host")
        core.tasks.start()
        defer { core.tasks.stop() }
        let id = HostSessionID()
        #expect(await core.tasks.agentServers(for: id, agent: spec.id, base: []).isEmpty)
        let base: JSONValue = .object([
            "claudeCode": .object(["options": .object(["settings": .object(["deniedMcpServers": .array([])])])])
        ])
        let meta = await core.tasks.agentMeta(for: id, agent: spec.id, base: base)
        #expect(meta?["claudeCode"]?["options"]?["settings"] != nil)
        let endpoint = try #require(
            meta?["claudeCode"]?["options"]?["env"]?[NativeActionCLI.endpointVariable]?.stringValue)
        #expect(try NativeActionCommand.endpoint(endpoint).host == "127.0.0.1")
        #expect(meta?["claudeCode"]?["options"]?["plugins"] != nil)
        let other = await core.tasks.agentMeta(for: HostSessionID(), agent: spec.id, base: base)
        #expect(other?["claudeCode"]?["options"]?["env"]?[NativeActionCLI.endpointVariable]?.stringValue != endpoint)
        #expect(base["claudeCode"]?["options"]?["env"] == nil)
        var optedIn = spec
        optedIn.nativeMCPEnabled = true
        try core.syncAgents([optedIn])
        #expect(await core.tasks.agentServers(for: id, agent: spec.id, base: []).count == 1)
        var unsupported = spec
        unsupported.nativeSkill = nil
        try core.syncAgents([unsupported])
        _ = core.tasks.prepareSkill(for: unsupported, environment: [:])
        #expect(await core.tasks.agentServers(for: id, agent: spec.id, base: []).count == 1)
        #expect(await core.tasks.agentMeta(for: id, agent: spec.id, base: base) == base)
    }

    @Test("Development Codex installs only in its own host folder; user-owned skills keep MCP")
    func isolatedCodex() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "host-skill-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let core = try host(root)
        let spec = AgentSpec(id: "fixture", name: "Fixture", command: "/fixture", nativeSkill: .codex)
        try core.syncAgents([spec])
        let own = root.appending(path: "codex")
        _ = core.tasks.prepareSkill(for: spec, environment: ["CODEX_HOME": own.path])
        #expect(!core.tasks.usesMCP(agent: spec.id))
        let file = own.appending(path: "skills/native-app/SKILL.md")
        try Data("user changed it".utf8).write(to: file)
        _ = core.tasks.prepareSkill(for: spec, environment: ["CODEX_HOME": own.path])
        #expect(core.tasks.usesMCP(agent: spec.id))
        #expect(try String(contentsOf: file, encoding: .utf8) == "user changed it")
        _ = core.tasks.prepareSkill(for: spec, environment: ["CODEX_HOME": "/outside-this-host"])
        #expect(core.tasks.usesMCP(agent: spec.id))
    }

    @Test("The default app-served endpoint is retained for the skill and omitted from MCP")
    func appEndpoint() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "host-skill-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let core = try host(root)
        let spec = AgentSpec(id: "fixture", name: "Fixture", command: "/fixture", nativeSkill: .claudeCode)
        try core.syncAgents([spec])
        try core.tasks.configure(ConfigureTasksParams(servesTools: false), from: UUID())
        _ = core.tasks.prepareSkill(for: spec, environment: [:])
        let servers: [JSONValue] = [
            .object(["name": .string("native"), "url": .string("http://127.0.0.1:1234/mcp/app-token")])
        ]
        let id = HostSessionID()
        #expect(await core.tasks.agentServers(for: id, agent: spec.id, base: servers).isEmpty)
        let meta = await core.tasks.agentMeta(for: id, agent: spec.id, base: nil, servers: servers)
        #expect(
            meta?["claudeCode"]?["options"]?["env"]?[NativeActionCLI.endpointVariable]?.stringValue
                == "http://127.0.0.1:1234/mcp/app-token")
    }

    @Test("Revoking Native tools denies existing skill endpoints as well as MCP")
    func revoked() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "host-skill-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let core = try host(root)
        let spec = AgentSpec(id: "fixture", name: "Fixture", command: "/fixture", nativeSkill: .claudeCode)
        try core.syncAgents([spec])
        _ = core.tasks.prepareSkill(for: spec, environment: [:])
        core.tasks.start()
        defer { core.tasks.stop() }
        let id = HostSessionID()
        let record = StoredSession(
            id: id, agentID: spec.id, agentSessionID: SessionID("fixture-session"), cwd: root.path, parentID: nil,
            origin: .user)
        core.sessions[id] = HostSession(record: record, agentName: spec.name, phase: .idle, needsLoad: false)
        let url = try #require(await core.tasks.toolURL(for: id))
        #expect(
            try await NativeActionClient.call(NativeActionCommand(["list_agents"]), endpoint: url.absoluteString)
                .contains("Fixture"))
        core.apply(.blocked("fixture policy"))
        #expect(await core.tasks.toolURL(for: id) == nil)
        #expect(core.tasks.admittedCaller(of: id.rawValue) == nil)
        await #expect(throws: (any Error).self) {
            try await NativeActionClient.call(NativeActionCommand(["list_agents"]), endpoint: url.absoluteString)
        }
    }
}
#endif
