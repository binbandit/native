import Foundation
import MCP
import Testing

@testable import MCPClient

@Suite struct SessionTests {
    private func connect() async throws -> MCPSession {
        let config = MCPServerConfig(
            name: "fake",
            transport: .stdio(
                command: "/bin/sh", arguments: [Fixture.url("fake-mcp-server.sh").path(percentEncoded: false), "clean"]))
        return try await MCPSession.connect(
            config, environment: ProcessInfo.processInfo.environment, directory: nil, launcher: LocalStdioLauncher())
    }

    @Test func listsToolsWithTheirSchemas() async throws {
        let session = try await connect()
        defer { Task { await session.close() } }

        #expect(session.tools.map(\.info.name) == ["search", "delete"])
        #expect(session.tools.first?.inputSchema?["required"] == ["query"])
        #expect(session.tools.first?.info.isReadOnly == true)
    }

    @Test func callsATool() async throws {
        let session = try await connect()
        defer { Task { await session.close() } }

        let result = try await session.call("search", arguments: ["query": "thing"])
        #expect(result["structuredContent"]?["matches"] == ["thing"])

        let failed = try await session.call("delete", arguments: ["id": "x"])
        #expect(failed["isError"] == true)
    }
}
