import ACP
import Exec
import Foundation
import MCPClient

@testable import Native

private struct FixtureFiles: ConfigFileSystem {
    func contents(atPath path: String) -> Data? {
        guard path == "/fixture/.codex/config.toml" else { return nil }
        return Data("[mcp_servers.docs]\nurl = \"https://docs.example.com/mcp\"\n".utf8)
    }

    func fileExists(atPath path: String) -> Bool { contents(atPath: path) != nil }
}

private actor FixtureRunner: CommandRunner {
    var status = "o_auth"
    let capture: String

    init(capture: Data) { self.capture = String(decoding: capture, as: UTF8.self) }

    func setStatus(_ value: String) { status = value }

    func run(_ command: Command) async throws -> CommandResult {
        let output = capture.replacingOccurrences(of: "\"o_auth\"", with: "\"\(status)\"")
        return CommandResult(exitCode: 0, standardOutput: Data(output.utf8), standardError: Data())
    }
}

@MainActor
private final class FixtureHost: MCPLibraryHost {
    var mcpAgents: [MCPAgent] {
        BuiltInPlugins.codex.manifest.agents.map {
            let definition = AgentDefinition($0, pluginID: "codex")
            return MCPAgent(
                id: definition.id, definition: definition, name: "Codex", symbol: "terminal", format: .codex,
                transports: nil, isRunning: false)
        }
    }
    var mcpProjects: [URL] { [URL(filePath: "/fixture/project")] }
    var mcpContextReports: [SessionKey: ContextReport] { [:] }
    var mcpAgentsAwaitingRestart: [MCPAgent] { [] }
    func mcpEnvironment() async -> [String: String] { ["HOME": "/fixture"] }
    func mcpPluginServers(for session: SessionContext?) -> [MCPPluginServer] { [] }
    func mcpPolicySupport(for agent: AgentDefinition.ID) -> SessionPolicySupport { .perSession }
    func mcpApplyLaunchPolicies(force: Bool) async {}
    func mcpScriptSession(_ clientID: UUID) -> (any MCPScriptSessionLink)? { nil }
}

@main
@MainActor
private struct MCPAuthRegression {
    static func main() async throws {
        let runner = FixtureRunner(capture: try Data(contentsOf: URL(filePath: CommandLine.arguments[1])))
        let library = MCPLibrary(
            runner: runner, files: FixtureFiles(), secretStore: MemorySecretStore(),
            storeURL: nil)
        library.host = FixtureHost()
        await library.readConfigurations()
        let tasks = ["/fixture/project", "/fixture/worktree"].map {
            SessionContext(
                clientID: UUID(), agent: AgentDefinition.ID(rawValue: "codex"), agentName: "Codex",
                cwd: URL(filePath: $0))
        }
        for task in tasks { await library.track(task) }
        guard let server = library.configuration(of: .codex)?.servers.first else {
            fatalError("Fixture server missing")
        }
        let key = MCPServerKey.agent(server.id)
        library.reports[key] = MCPProbeReport(
            status: .needsAuth(MCPAuthChallenge(statusCode: 401, sentCredentials: false)),
            startedAt: .now, duration: .zero)
        guard !library.health(of: key).needsAttention else {
            print("FAIL: shared OAuth sign-in is displayed as \(library.health(of: key).label)")
            exit(1)
        }
        expectSharedSignIn(library, tasks: tasks, signedIn: true)
        await runner.setStatus("not_logged_in")
        await library.readConfigurations()
        guard library.health(of: key).needsAttention else {
            print("FAIL: signing out must refresh the existing server")
            exit(1)
        }
        expectSharedSignIn(library, tasks: tasks, signedIn: false)
        await runner.setStatus("o_auth")
        await library.readConfigurations()
        guard !library.health(of: key).needsAttention else {
            print("FAIL: signing in from another task must replace the old warning")
            exit(1)
        }
        expectSharedSignIn(library, tasks: tasks, signedIn: true)
        print("PASS: shared sign-in, sign-out and sign-in again update the same MCP server")
    }

    private static func expectSharedSignIn(_ library: MCPLibrary, tasks: [SessionContext], signedIn: Bool) {
        for task in tasks {
            guard let entry = library.entries(forSession: task.clientID).first,
                (library.health(of: entry.key).label == "Signed in") == signedIn
            else {
                print("FAIL: the project and worktree tasks disagree about the shared sign-in")
                exit(1)
            }
        }
    }
}
