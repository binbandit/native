import Foundation
import MCP
import NativeOrchestration
import Testing

@Suite("Native action CLI")
struct NativeActionTests {
    @Test("Arguments preserve JSON text and support stdin and text output")
    func arguments() throws {
        let command = try NativeActionCommand(["send_message", "--stdin", "--text"]) {
            Data(#"{"to":"parent","message":"Quote: \"hi\"\nnext line"}"#.utf8)
        }
        #expect(command.tool == "send_message")
        #expect(command.arguments["message"]?.stringValue == "Quote: \"hi\"\nnext line")
        #expect(command.text)
        #expect(try NativeActionCommand(["list_tasks"]).arguments == [:])
    }

    @Test("Unknown actions, ambiguous arguments, nonobjects and oversized input fail before connecting")
    func invalidArguments() {
        for arguments in [
            [], ["delete_everything"], ["list_tasks", "[]"], ["list_tasks", "null"],
            ["list_tasks", "{broken"], ["list_tasks", "{}", "extra"], ["--text", "list_tasks"],
        ] {
            #expect(throws: (any Error).self) { try NativeActionCommand(arguments) }
        }
        #expect(throws: (any Error).self) {
            try NativeActionCommand(["run_script", "--stdin"]) { Data(repeating: 32, count: 4 * 1024 * 1024 + 1) }
        }
    }

    @Test("Session credentials cannot send requests to arbitrary destinations")
    func destinations() throws {
        #expect(try NativeActionCommand.endpoint("http://127.0.0.1:1234/mcp/signed-token").port == 1234)
        for value in [
            "https://example.com/mcp/token", "http://127.0.0.1:1234/other/token",
            "http://user:password@127.0.0.1:1234/mcp/token", "http://127.0.0.1:1234/mcp/token?secret=x",
            "http://127.0.0.1:1234/mcp/token#part", "http://localhost:1234/mcp/token", "file:///tmp/token",
        ] {
            #expect(throws: (any Error).self) { try NativeActionCommand.endpoint(value) }
        }
    }

    @Test("A thread needs its own credential and cannot traverse another path")
    func threadIdentity() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "native-cli-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let thread = UUID().uuidString.lowercased()
        let endpoint = "http://127.0.0.1:1234/mcp/signed-token"
        try JSONEncoder().encode(NativeActionCLI.Credential(endpoint: endpoint))
            .write(to: root.appending(path: thread + ".json"))
        #expect(
            try NativeActionCLI.endpoint(environment: [
                NativeActionCLI.sessionsVariable: root.path, "CODEX_THREAD_ID": thread,
            ]) == endpoint)
        for id in ["../../other", UUID().uuidString, ""] {
            #expect(throws: (any Error).self) {
                try NativeActionCLI.endpoint(environment: [
                    NativeActionCLI.sessionsVariable: root.path, "CODEX_THREAD_ID": id,
                ])
            }
        }
        #expect(throws: (any Error).self) { try NativeActionCLI.endpoint(environment: [:]) }
    }

    #if canImport(Network)
    @Test("The CLI uses the endpoint's authorization, JSON results, and tool errors")
    func permission() async throws {
        let tool = MCPTool<String>(
            name: "list_tasks", description: "Fixture", inputSchema: [:], arguments: JSON.self
        ) { caller, _ in
            if caller == "denied" { throw MCPToolError("This task cannot read another task.") }
            return MCPToolResult(text: "No tasks", structuredContent: ["tasks": []])
        }
        let server = MCPHTTPServer(name: "fixture", version: "1", tools: [tool]) { token in
            ["allowed", "denied"].contains(token) ? token : nil
        }
        try await server.start()
        defer { server.stop() }
        let command = try NativeActionCommand(["list_tasks"])
        let allowed = try #require(server.url(for: "allowed"))
        #expect(try await NativeActionClient.call(command, endpoint: allowed.absoluteString) == #"{"tasks":[]}"#)
        #expect(
            try await NativeActionClient.call(
                NativeActionCommand(["list_tasks", "--text"]), endpoint: allowed.absoluteString) == "No tasks")
        let forged = try #require(server.url(for: "forged"))
        await #expect(throws: (any Error).self) {
            try await NativeActionClient.call(command, endpoint: forged.absoluteString)
        }
        let denied = try #require(server.url(for: "denied"))
        await #expect(throws: (any Error).self) {
            try await NativeActionClient.call(command, endpoint: denied.absoluteString)
        }
    }
    #endif
}
