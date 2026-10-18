import Foundation
import Testing

@testable import MCP

@Suite struct ListingTests {
    struct None: Decodable, Sendable {}

    /// A tool that tells each client what it can reach, and drops its read-only hint for "bob".
    let endpoint: MCPEndpoint<String> = {
        var tool = MCPTool<String>(
            name: "run", description: "Runs things.", inputSchema: ["type": "object"],
            annotations: MCPToolAnnotations(readOnly: true), arguments: None.self
        ) { _, _ in MCPToolResult(text: "ran") }
        tool.listing = { owner in
            MCPTool<String>.Listing(
                description: "Runs things for \(owner).", annotations: MCPToolAnnotations(readOnly: owner == "alice"))
        }
        return MCPHTTPServer(name: "test", version: "1.0", tools: [tool]) { token in
            ["alice", "bob"].contains(token) ? token : nil
        }.endpoint
    }()

    @Test func eachClientSeesItsOwnListing() async throws {
        func listed(by owner: String) async throws -> JSON {
            var request = legacy("tools/list")
            request.path = "/mcp/\(owner)"
            return try #require(await endpoint.respond(to: request).json?["result"]?["tools"]?.arrayValue?.first)
        }
        let alice = try await listed(by: "alice")
        let bob = try await listed(by: "bob")
        #expect(alice["description"] == "Runs things for alice.")
        #expect(alice["annotations"]?["readOnlyHint"] == true)
        #expect(bob["annotations"]?["readOnlyHint"] == false)

        let modernList = try #require(await endpoint.respond(to: modern("tools/list")).json?["result"])
        #expect(modernList["cacheScope"] == nil)
    }
}
