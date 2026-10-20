import Foundation

@testable import MCP

/// Tools that echo, fail, and run until cancelled (reporting both to `events`).
func makeTools(events: AsyncStream<String>.Continuation? = nil) -> [MCPTool<String>] {
    struct Echo: Decodable, Sendable {
        var text: String
    }
    struct None: Decodable, Sendable {}

    let echo = MCPTool<String>(
        name: "echo",
        description: "Echoes text back.",
        inputSchema: ["type": "object", "properties": ["text": ["type": "string"]], "required": ["text"]],
        annotations: MCPToolAnnotations(readOnly: true),
        arguments: Echo.self
    ) { owner, arguments in
        MCPToolResult(
            text: "\(owner): \(arguments.text)",
            structuredContent: ["owner": .string(owner), "text": .string(arguments.text)])
    }
    let fail = MCPTool<String>(
        name: "fail", description: "Always fails.", inputSchema: ["type": "object"], arguments: None.self
    ) { _, _ in
        throw MCPToolError("That didn't work.")
    }
    // Runs until it's cancelled, reporting both.
    let slow = MCPTool<String>(
        name: "slow", description: "Takes a while.", inputSchema: ["type": "object"], arguments: None.self
    ) { _, _ in
        events?.yield("started")
        do {
            try await Task.sleep(for: .seconds(60))
        } catch {
            events?.yield("cancelled")
        }
        return MCPToolResult(text: "done")
    }
    return [echo, fail, slow]
}

/// An endpoint whose tokens name their owners: "alice" and "bob" exist, anything else doesn't.
func makeEndpoint(events: AsyncStream<String>.Continuation? = nil) -> MCPEndpoint<String> {
    MCPEndpoint(name: "test", version: "1.0", instructions: "Use echo.", tools: makeTools(events: events)) { token in
        ["alice", "bob"].contains(token) ? token : nil
    }
}

#if canImport(Network)
/// `makeEndpoint`'s tools and tokens, served over HTTP.
func makeServer(events: AsyncStream<String>.Continuation? = nil) -> MCPHTTPServer<String> {
    MCPHTTPServer(name: "test", version: "1.0", instructions: "Use echo.", tools: makeTools(events: events)) { token in
        ["alice", "bob"].contains(token) ? token : nil
    }
}
#endif

func post(_ body: JSON, token: String = "alice", headers: [String: String] = [:]) -> HTTPRequest {
    let base = [
        "host": "127.0.0.1:4242", "content-type": "application/json", "accept": "application/json, text/event-stream",
    ]
    return HTTPRequest(
        method: "POST",
        path: "/mcp/\(token)",
        headers: base.merging(headers.map { ($0.key.lowercased(), $0.value) }) { $1 },
        body: body.encoded()
    )
}

/// A request in the stateless revision, with the headers that mirror its body.
func modern(
    _ method: String, params: [String: JSON] = [:], version: String = "2026-07-28", headers: [String: String] = [:]
) -> HTTPRequest {
    var params = params
    params["_meta"] = [
        "io.modelcontextprotocol/protocolVersion": .string(version),
        "io.modelcontextprotocol/clientInfo": ["name": "tests", "version": "0"],
        "io.modelcontextprotocol/clientCapabilities": [:],
    ]
    var mirrored = ["MCP-Protocol-Version": version, "Mcp-Method": method]
    if method == "tools/call", let name = params["name"]?.stringValue {
        mirrored["Mcp-Name"] = name
    }
    return post(
        ["jsonrpc": "2.0", "id": 1, "method": .string(method), "params": .object(params)],
        headers: mirrored.merging(headers) { $1 })
}

func legacy(_ method: String, params: [String: JSON] = [:], version: String? = "2025-11-25") -> HTTPRequest {
    post(
        ["jsonrpc": "2.0", "id": 7, "method": .string(method), "params": .object(params)],
        headers: version.map { ["MCP-Protocol-Version": $0] } ?? [:])
}

extension HTTPResponse {
    var json: JSON? {
        try? JSONDecoder().decode(JSON.self, from: body)
    }
}
