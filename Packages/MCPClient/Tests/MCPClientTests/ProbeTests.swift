import Foundation
import MCP
import MCPClient
import Testing

@Suite("Probing servers")
struct ProbeTests {
    let probe = MCPProbe(clientVersion: "1.0", timeout: .seconds(10), launcher: LocalStdioLauncher())
    let environment = ["PATH": "/usr/bin:/bin"]

    private func fake(_ mode: String? = nil) -> MCPServerConfig {
        MCPServerConfig(
            name: "fake",
            transport: .stdio(
                command: "/bin/sh",
                arguments: [Fixture.url("fake-mcp-server.sh").path(percentEncoded: false)] + (mode.map { [$0] } ?? [])))
    }

    @Test func listsAStdioServersToolsAcrossPages() async throws {
        let report = await probe.probe(fake(), environment: environment, directory: nil)
        #expect(report.status == .connected)
        #expect(report.transport == .stdio)
        #expect(
            report.server
                == MCPServerInfo(
                    name: "fake", title: "Fake Server", version: "1.2.3", protocolVersion: "2025-06-18",
                    instructions: "Use the fake tools."))
        #expect(report.tools.map(\.name) == ["search", "delete"])
        let search = try #require(report.tools.first)
        #expect(search.parameters == ["query", "limit"])
        #expect(search.isReadOnly == true)
        #expect(report.tools.last?.isDestructive == true)
        #expect(report.toolDefinitionBytes > 200)
        #expect(report.tools.map(\.definitionBytes).reduce(0, +) == report.toolDefinitionBytes)
        #expect(report.stderr.contains("fake server starting"))
    }

    @Test func aServerThatExitsShowsItsStatusAndStderr() async {
        let report = Self.failure(await probe.probe(fake("crash"), environment: environment, directory: nil))
        #expect(report?.exitStatus == 3)
        #expect(report?.message.contains("exited with status 3") == true)
    }

    @Test func stderrSurvivesTheFailure() async {
        let report = await probe.probe(fake("crash"), environment: environment, directory: nil)
        #expect(report.stderr.contains("missing API key"))
    }

    @Test func aMissingCommandSaysSo() async {
        let server = MCPServerConfig(name: "nope", transport: .stdio(command: "definitely-not-installed-mcp"))
        let failure = Self.failure(await probe.probe(server, environment: environment, directory: nil))
        #expect(failure?.stage == .launch)
        #expect(failure?.message == "Couldn't find definitely-not-installed-mcp on your PATH.")
    }

    @Test func aSilentServerTimesOutAndIsStopped() async {
        let quick = MCPProbe(timeout: .seconds(1), launcher: LocalStdioLauncher())
        let clock = ContinuousClock()
        let start = clock.now
        let failure = Self.failure(await quick.probe(fake("hang"), environment: environment, directory: nil))
        #expect(failure?.message == "fake didn't answer within 1 second.")
        #expect(clock.now - start < .seconds(6))
    }

    @Test func listsAStreamableHTTPServersTools() async throws {
        let server = MCPHTTPServer<String>(name: "native-test", version: "2.0", instructions: "Hi.", tools: [Self.echo])
        { $0 == "token" ? $0 : nil }
        try await server.start()
        defer { server.stop() }
        let url = try #require(server.url(for: "token"))
        let report = await probe.probe(
            MCPServerConfig(name: "native", transport: .http(url: url)), environment: [:], directory: nil)
        #expect(report.status == .connected)
        #expect(report.server?.name == "native-test")
        #expect(report.tools.map(\.name) == ["echo"])
        #expect(report.tools.first?.isReadOnly == true)
    }

    @Test func aURLThatSpeaksNeitherTransportFails() async throws {
        let server = MCPHTTPServer<String>(name: "native-test", version: "2.0", tools: [Self.echo]) { _ in nil }
        try await server.start()
        defer { server.stop() }
        let url = try #require(server.url(for: "unknown"))
        let failure = Self.failure(
            await probe.probe(
                MCPServerConfig(name: "native", transport: .http(url: url)), environment: [:], directory: nil))
        #expect(failure?.message == "The server answered HTTP 404 and doesn't speak SSE either.")
    }

    @Test func aServerAskingForSignInNeedsAuth() async throws {
        let stub = try await StubHTTPServer { _ in
            .init(
                status: 401,
                headers: [
                    "WWW-Authenticate":
                        #"Bearer error="invalid_token", resource_metadata="https://auth.example.com/.well-known/oauth-protected-resource""#
                ])
        }
        defer { stub.stop() }
        let report = await probe.probe(
            MCPServerConfig(name: "docs", transport: .http(url: stub.url)), environment: [:], directory: nil)
        #expect(
            report.status
                == .needsAuth(
                    MCPAuthChallenge(
                        statusCode: 401,
                        resourceMetadata: URL(string: "https://auth.example.com/.well-known/oauth-protected-resource"),
                        sentCredentials: false)))
    }

    @Test func readsRepliesFromEventStreamsAndKeepsTheSession() async throws {
        let stub = try await StubHTTPServer { request in
            if request.body.contains(#""method":"initialize""#) {
                let event =
                    #"{"jsonrpc":"2.0","id":1,"result":{"protocolVersion":"2025-06-18","capabilities":{"tools":{}},"serverInfo":{"name":"streamer"}}}"#
                return .init(
                    status: 200, headers: ["Content-Type": "text/event-stream", "Mcp-Session-Id": "s-1"],
                    body: ": comment\nevent: message\ndata: \(event)\n\n")
            }
            if request.body.contains("notifications/initialized") { return .init(status: 202) }
            guard request.headers["mcp-session-id"] == "s-1", request.headers["mcp-protocol-version"] == "2025-06-18"
            else { return .init(status: 400) }
            if request.method == "DELETE" { return .init(status: 200) }
            return .init(
                status: 200, headers: ["Content-Type": "application/json"],
                body:
                    #"{"jsonrpc":"2.0","id":2,"result":{"tools":[{"name":"stream","inputSchema":{"type":"object"}}]}}"#)
        }
        defer { stub.stop() }
        let report = await probe.probe(
            MCPServerConfig(name: "streamer", transport: .http(url: stub.url, headers: ["X-Key": "k"])),
            environment: [:], directory: nil)
        #expect(report.status == .connected)
        #expect(report.tools.map(\.name) == ["stream"])
        #expect(stub.requests.allSatisfy { $0.headers["x-key"] == "k" })
        #expect(stub.requests.last?.method == "DELETE")
    }

    private static let echo = MCPTool<String>(
        name: "echo",
        description: "Echoes text back.",
        inputSchema: ["type": "object", "properties": ["text": ["type": "string"]]],
        annotations: MCPToolAnnotations(readOnly: true),
        arguments: [String: String].self
    ) { _, _ in
        MCPToolResult(text: "called")
    }

    private static func failure(_ report: MCPProbeReport) -> MCPProbeFailure? {
        guard case .failed(let failure) = report.status else { return nil }
        return failure
    }
}
