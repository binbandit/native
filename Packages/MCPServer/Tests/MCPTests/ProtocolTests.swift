import Foundation
import Testing

@testable import MCP

struct ProtocolTests {
    let endpoint = makeServer().endpoint

    // MARK: - Endpoint

    @Test func unknownTokensAreNotFound() async {
        #expect(await endpoint.respond(to: legacy("ping")).status == 200)
        var request = legacy("ping")
        request.path = "/mcp/mallory"
        #expect(await endpoint.respond(to: request).status == 404)
        request.path = "/mcp/"
        #expect(await endpoint.respond(to: request).status == 404)
        request.path = "/mcp/alice/extra"
        #expect(await endpoint.respond(to: request).status == 404)
    }

    @Test func onlyPostIsAllowed() async {
        for method in ["GET", "DELETE"] {
            var request = legacy("ping")
            request.method = method
            let response = await endpoint.respond(to: request)
            #expect(response.status == 405)
            #expect(response.headers["Allow"] == "POST")
        }
    }

    @Test func browserRequestsAreForbidden() async {
        // DNS rebinding: a page on another origin, or reaching loopback through its own hostname.
        #expect(
            await endpoint.respond(
                to: post(["jsonrpc": "2.0", "id": 1, "method": "ping"], headers: ["Origin": "https://evil.example"])
            ).status == 403)
        #expect(
            await endpoint.respond(
                to: post(["jsonrpc": "2.0", "id": 1, "method": "ping"], headers: ["Host": "evil.example:4242"])
            ).status == 403)
        #expect(
            await endpoint.respond(
                to: post(["jsonrpc": "2.0", "id": 1, "method": "ping"], headers: ["Host": "localhost:4242"])
            ).status == 200)
    }

    @Test func notificationsAreAcceptedWithoutABody() async {
        let response = await endpoint.respond(to: post(["jsonrpc": "2.0", "method": "notifications/initialized"]))
        #expect(response.status == 202)
        #expect(response.body.isEmpty)
    }

    @Test func malformedBodiesAreBadRequests() async {
        var request = legacy("ping")
        request.body = Data("{nope".utf8)
        let response = await endpoint.respond(to: request)
        #expect(response.status == 400)
        #expect(response.json?["error"]?["code"] == -32700)
        #expect(
            await endpoint.respond(to: post([["jsonrpc": "2.0", "id": 1, "method": "ping"]])).json?["error"]?["code"]
                == -32600)
    }

    // MARK: - Initialize-based revisions

    @Test(arguments: [
        ("2025-11-25", "2025-11-25"), ("2025-06-18", "2025-06-18"), ("2025-03-26", "2025-03-26"),
        ("2024-11-05", "2025-11-25"), ("1999-01-01", "2025-11-25"),
    ])
    func initializeAgreesOnAVersion(requested: String, agreed: String) async throws {
        let response = await endpoint.respond(
            to: legacy(
                "initialize",
                params: [
                    "protocolVersion": .string(requested),
                    "capabilities": [:],
                    "clientInfo": ["name": "claude-code", "version": "2"],
                ], version: nil))
        let result = try #require(response.json?["result"])
        #expect(response.json?["id"] == 7)
        #expect(result["protocolVersion"] == .string(agreed))
        #expect(result["capabilities"]?["tools"] != nil)
        #expect(result["serverInfo"] == ["name": "test", "version": "1.0"])
        #expect(result["instructions"] == "Use echo.")
        #expect(result["resultType"] == nil)
    }

    @Test func listsToolsWithTheirSchemas() async throws {
        let tools = try #require(await endpoint.respond(to: legacy("tools/list")).json?["result"]?["tools"])
        guard case .array(let list) = tools else {
            Issue.record("Expected an array of tools")
            return
        }
        #expect(list.compactMap { $0["name"]?.stringValue } == ["echo", "fail", "slow"])
        #expect(list[0]["description"] == "Echoes text back.")
        #expect(list[0]["inputSchema"]?["required"] == ["text"])
        #expect(list[0]["annotations"] == ["readOnlyHint": true])
        #expect(list[1]["annotations"] == nil)
    }

    @Test func callsReachTheToolWithTheTokensContext() async throws {
        for token in ["alice", "bob"] {
            var request = legacy("tools/call", params: ["name": "echo", "arguments": ["text": "hi"]])
            request.path = "/mcp/\(token)"
            let result = try #require(await endpoint.respond(to: request).json?["result"])
            #expect(result["content"] == [["type": "text", "text": .string("\(token): hi")]])
            #expect(result["structuredContent"] == ["owner": .string(token), "text": "hi"])
            #expect(result["isError"] == false)
        }
    }

    @Test func toolFailuresAreResultsTheModelCanRead() async throws {
        let failed = try #require(
            await endpoint.respond(to: legacy("tools/call", params: ["name": "fail"])).json?["result"])
        #expect(failed["isError"] == true)
        #expect(failed["content"]?[0]?["text"] == "That didn't work.")

        let invalid = try #require(
            await endpoint.respond(to: legacy("tools/call", params: ["name": "echo", "arguments": ["txt": "hi"]]))
                .json?["result"])
        #expect(invalid["isError"] == true)
        #expect(invalid["content"]?[0]?["text"] == "Invalid arguments for echo: missing required argument \"text\".")
    }

    @Test func unknownToolsAndMethodsAreProtocolErrors() async {
        let unknownTool = await endpoint.respond(to: legacy("tools/call", params: ["name": "nope"]))
        #expect(unknownTool.status == 200)
        #expect(unknownTool.json?["error"]?["code"] == -32602)
        let unknownMethod = await endpoint.respond(to: legacy("resources/list"))
        #expect(unknownMethod.json?["error"]?["code"] == -32601)
    }

    @Test func unsupportedVersionHeadersAreRejected() async {
        #expect(await endpoint.respond(to: legacy("tools/list", version: "2024-11-05")).status == 400)
        // Clients before 2025-06-18 don't send the header at all.
        #expect(await endpoint.respond(to: legacy("tools/list", version: nil)).status == 200)
    }

    // MARK: - Stateless revision

    @Test func discoverDescribesTheServer() async throws {
        let response = await endpoint.respond(to: modern("server/discover"))
        #expect(response.status == 200)
        let result = try #require(response.json?["result"])
        #expect(result["resultType"] == "complete")
        #expect(result["supportedVersions"] == ["2026-07-28", "2025-11-25", "2025-06-18", "2025-03-26"])
        #expect(result["capabilities"]?["tools"] != nil)
        #expect(result["_meta"]?["io.modelcontextprotocol/serverInfo"] == ["name": "test", "version": "1.0"])
        #expect(result["instructions"] == "Use echo.")
        #expect(result["ttlMs"] != nil)
        #expect(result["cacheScope"] == "public")
    }

    @Test func modernCallsWork() async throws {
        let list = try #require(await endpoint.respond(to: modern("tools/list")).json?["result"])
        #expect(list["resultType"] == "complete")
        #expect(list["ttlMs"] != nil)

        let call = try #require(
            await endpoint.respond(to: modern("tools/call", params: ["name": "echo", "arguments": ["text": "hi"]]))
                .json?["result"])
        #expect(call["resultType"] == "complete")
        #expect(call["content"]?[0]?["text"] == "alice: hi")
    }

    @Test func encodedToolNamesMatch() async throws {
        let encoded = "=?base64?\(Data("echo".utf8).base64EncodedString())?="
        let response = await endpoint.respond(
            to: modern(
                "tools/call", params: ["name": "echo", "arguments": ["text": "hi"]], headers: ["Mcp-Name": encoded]))
        #expect(response.json?["result"]?["content"]?[0]?["text"] == "alice: hi")
    }

    @Test(arguments: [["Mcp-Method": "tools/list"], ["Mcp-Name": "fail"], ["MCP-Protocol-Version": "2025-11-25"]])
    func headersThatDisagreeWithTheBodyAreRejected(headers: [String: String]) async {
        let response = await endpoint.respond(
            to: modern("tools/call", params: ["name": "echo", "arguments": ["text": "hi"]], headers: headers))
        #expect(response.status == 400)
        #expect(response.json?["error"]?["code"] == -32020)
        #expect(response.json?["id"] == 1)
    }

    @Test func unsupportedVersionsListTheSupportedOnes() async {
        let response = await endpoint.respond(to: modern("tools/list", version: "2099-01-01"))
        #expect(response.status == 400)
        #expect(response.json?["error"]?["code"] == -32022)
        #expect(response.json?["error"]?["data"]?["requested"] == "2099-01-01")
        #expect(response.json?["error"]?["data"]?["supported"]?[0] == "2026-07-28")
    }

    @Test func modernRequestsMustDeclareTheirMetadata() async {
        let request = post(
            ["jsonrpc": "2.0", "id": 1, "method": "tools/list"],
            headers: ["MCP-Protocol-Version": "2026-07-28", "Mcp-Method": "tools/list"])
        let response = await endpoint.respond(to: request)
        #expect(response.status == 400)
        #expect(response.json?["error"]?["code"] == -32602)
    }

    @Test func unknownModernMethodsAreNotFound() async {
        let response = await endpoint.respond(to: modern("resources/list"))
        #expect(response.status == 404)
        #expect(response.json?["error"]?["code"] == -32601)
    }
}

extension JSON {
    fileprivate subscript(index: Int) -> JSON? {
        guard case .array(let array) = self, array.indices.contains(index) else { return nil }
        return array[index]
    }
}
