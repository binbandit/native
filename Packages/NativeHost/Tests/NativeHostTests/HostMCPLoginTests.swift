import Exec
import Foundation
import MCPClient
import NativeHostClient
import Testing

/// Opt-in integration check driven by scripts/tests/mcp-login.py, using a loopback OAuth server
/// and a private Claude credential namespace. It never opens a browser or uses a real account.
@Suite("MCP OAuth through the real CLI", .timeLimit(.minutes(2)))
struct HostMCPLoginTests {
    @Test(.enabled(if: ProcessInfo.processInfo.environment["NATIVE_MCP_LOGIN_CLI"] != nil))
    @MainActor func localLoopbackAndPairedPaste() async throws {
        let settings = ProcessInfo.processInfo.environment
        let executable = try #require(settings["NATIVE_MCP_LOGIN_CLI"])
        let directory = try #require(settings["NATIVE_MCP_LOGIN_CONFIG"])
        let isCodex = settings["NATIVE_MCP_LOGIN_FORMAT"] == "codex"
        var overrides = [
            "CLAUDE_CONFIG_DIR": directory, "CLAUDE_SECURESTORAGE_CONFIG_DIR": directory,
            "CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC": "1", "DISABLE_AUTOUPDATER": "1",
            "DISABLE_TELEMETRY": "1", "DISABLE_ERROR_REPORTING": "1", "TERM": "dumb",
        ]
        if isCodex { overrides["CODEX_HOME"] = directory }
        let environment = settings.merging(overrides) { $1 }
        var command = Command(
            executable, ["mcp", "login", "fixture", "--no-browser"], environment: environment, timeout: .seconds(30))
        if !isCodex {
            let before = try await LocalCommandRunner().run(command)
            #expect(!before.succeeded)
            #expect((before.output + before.errorOutput).contains("stdin isn't a terminal"))
        }

        let host = try await ExecHost.make()
        let paired = try await host.connect(ExecHost.commandingDevice, name: "OAuth fixture client")
        for paste in [false, true] {
            let flow = MCPLoginFlow()
            defer { flow.cancel() }
            let runner: any CommandRunner = paste ? RemoteCommandRunner(client: paired) : LocalCommandRunner()
            command.environment = paste ? overrides : environment
            command.directory = paste ? host.projectPath : nil
            flow.start(command, runner: runner)
            try await wait { flow.phase == .waiting || !flow.isRunning }
            let authorization = try #require(flow.authorization)
            // This fixture endpoint replaces the browser. It checks and records the PKCE challenge,
            // then returns the redirect that a browser would visit or a remote user would paste.
            let (data, _) = try await URLSession.shared.data(from: authorization.url)
            let reply = try JSONDecoder().decode(AuthorizationReply.self, from: data)
            if paste {
                #expect(flow.submitCallback(reply.redirect.absoluteString))
            } else {
                _ = try await URLSession.shared.data(from: reply.redirect)
            }
            try await wait { !flow.isRunning }
            #expect(flow.phase == .succeeded)
            // A second CLI process must reload its own saved credentials and connect. Reading its
            // keychain item from the test executable would ask macOS for separate access permission.
            let check = try await runner.run(
                Command(
                    executable, isCodex ? ["mcp", "list", "--json"] : ["mcp", "get", "fixture"], in: command.directory,
                    environment: command.environment, timeout: .seconds(20)))
            #expect(check.succeeded)
            if isCodex {
                #expect(try CodexListing.decode(check.standardOutput).servers.first?.authentication == .signedIn)
            } else {
                #expect(check.output.contains("Connected"))
            }
        }
        await paired.stop()
        await host.stop()
    }

    private struct AuthorizationReply: Decodable { let redirect: URL }

    @MainActor private func wait(_ predicate: () -> Bool) async throws {
        let deadline = ContinuousClock.now + .seconds(35)
        while !predicate(), ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(20)) }
        try #require(predicate())
    }
}
