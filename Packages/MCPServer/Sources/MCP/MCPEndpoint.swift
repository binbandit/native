import Foundation

/// Answers HTTP requests to `/mcp/<token>` with MCP, independently of how they arrived.
///
/// Speaks both MCP eras: the stateless revision 2026-07-28, where every request declares its
/// protocol version, and the `initialize`-based revisions before it. Clients that know both (Claude
/// Code) probe with the modern `server/discover` and stay modern; others (Codex) initialize.
struct MCPEndpoint<Context: Sendable>: Sendable {
    let name: String
    let version: String
    let instructions: String?
    let tools: [MCPTool<Context>]
    let resolve: @Sendable (_ token: String) async -> Context?
    /// Tools offered to some clients only, or that come and go (another process answers them).
    var moreTools: (@Sendable (Context) async -> [MCPTool<Context>])? = nil

    /// Every tool `context` gets.
    private func tools(for context: Context) async -> [MCPTool<Context>] {
        tools + (await moreTools?(context) ?? [])
    }

    func respond(to request: HTTPRequest) async -> HTTPResponse {
        // DNS rebinding: a web page can reach loopback through a hostname it controls, but its
        // requests carry that Host and an Origin. MCP clients send neither.
        guard request.header("origin") == nil, Self.isLoopback(host: request.header("host")) else {
            return HTTPResponse(status: 403)
        }
        let token = request.path.dropFirst("/mcp/".count)
        guard request.path.hasPrefix("/mcp/"), !token.isEmpty, !token.contains("/"),
            let context = await resolve(String(token))
        else {
            return HTTPResponse(status: 404)
        }
        // There are no server-initiated streams (GET) or protocol sessions to end (DELETE).
        guard request.method == "POST" else {
            return HTTPResponse(status: 405, headers: ["Allow": "POST"])
        }
        guard let message = try? JSONDecoder().decode(JSON.self, from: request.body) else {
            return .json(
                Self.envelope(id: .null, error: RPCFailure(code: -32700, message: "Parse error: the body isn't JSON.")),
                status: 400)
        }
        guard case .object(let fields) = message else {
            return .json(
                Self.envelope(
                    id: .null,
                    error: RPCFailure(
                        code: -32600, message: "Send one JSON-RPC message per request; batches aren't supported.")),
                status: 400)
        }
        // Notifications (no id) and responses (no method) need no answer, and nothing in them
        // changes what this server does.
        guard let method = fields["method"]?.stringValue, let id = fields["id"] else {
            return HTTPResponse(status: 202)
        }
        let params = fields["params"] ?? [:]

        let era = Self.era(of: request, method: method, params: params)
        do throws(RPCFailure) {
            var result = try await handle(method, params: params, era: era, request: request, context: context)
            if case .modern = era {
                result["resultType"] = "complete"
                result["_meta"] = ["io.modelcontextprotocol/serverInfo": serverInfo]
            }
            return .json(["jsonrpc": "2.0", "id": id, "result": .object(result)])
        } catch {
            return .json(Self.envelope(id: id, error: error), status: error.status)
        }
    }

    // MARK: - Eras

    private enum Era {
        /// Revision 2026-07-28 or later: stateless, with the version declared on every request.
        case modern
        /// An `initialize`-based revision.
        case legacy
    }

    private static var modernVersions: [String] { ["2026-07-28"] }
    /// Newest first: `initialize` offers the first when it doesn't speak the client's.
    private static var legacyVersions: [String] { ["2025-11-25", "2025-06-18", "2025-03-26"] }

    private static func era(of request: HTTPRequest, method: String, params: JSON) -> Era {
        let declared =
            params["_meta"]?["io.modelcontextprotocol/protocolVersion"]?.stringValue
            ?? request.header("mcp-protocol-version")
        // Versions are dates, so every later revision sorts after the first modern one.
        guard method != "initialize", let declared, declared >= modernVersions[0] else { return .legacy }
        return .modern
    }

    // MARK: - Methods

    private var serverInfo: JSON {
        ["name": .string(name), "version": .string(version)]
    }

    private var capabilities: JSON {
        ["tools": ["listChanged": false]]
    }

    private func definitions(for context: Context) async -> [JSON] {
        var definitions: [JSON] = []
        for tool in await tools(for: context) { definitions.append(await tool.definition(for: context)) }
        return definitions
    }

    private func handle(
        _ method: String, params: JSON, era: Era, request: HTTPRequest, context: Context
    ) async throws(RPCFailure) -> [String: JSON] {
        switch era {
        case .modern:
            try Self.validateModern(method, params: params, request: request)
        case .legacy:
            // After `initialize`, clients of 2025-06-18 and later repeat the agreed version.
            if method != "initialize", let version = request.header("mcp-protocol-version"),
                !Self.legacyVersions.contains(version)
            {
                throw RPCFailure(code: -32600, message: "Unsupported MCP-Protocol-Version \(version).", status: 400)
            }
        }

        // The tools never change while the server runs. Unless some vary by client, every client
        // gets the same ones, and may share them.
        let cacheHints: [String: JSON] =
            tools.contains { $0.listing != nil } || moreTools != nil
            ? ["ttlMs": 3_600_000] : ["ttlMs": 3_600_000, "cacheScope": "public"]
        switch (method, era) {
        case ("initialize", .legacy):
            let requested = params["protocolVersion"]?.stringValue
            var result: [String: JSON] = [
                "protocolVersion": .string(
                    requested.flatMap { Self.legacyVersions.contains($0) ? $0 : nil } ?? Self.legacyVersions[0]),
                "capabilities": capabilities,
                "serverInfo": serverInfo,
            ]
            result["instructions"] = instructions.map(JSON.string)
            return result
        case ("server/discover", .modern):
            var result: [String: JSON] = ["supportedVersions": Self.supportedVersions, "capabilities": capabilities]
            result["instructions"] = instructions.map(JSON.string)
            return result.merging(cacheHints) { $1 }
        case ("ping", _):
            return [:]
        case ("tools/list", .modern):
            return ["tools": .array(await definitions(for: context))].merging(cacheHints) { $1 }
        case ("tools/list", .legacy):
            return ["tools": .array(await definitions(for: context))]
        case ("tools/call", _):
            guard let name = params["name"]?.stringValue else {
                throw RPCFailure(code: -32602, message: "tools/call needs the name of a tool.")
            }
            guard let tool = await tools(for: context).first(where: { $0.name == name }) else {
                throw RPCFailure(code: -32602, message: "Unknown tool: \(name)")
            }
            let arguments = params["arguments"] ?? [:]
            guard arguments.objectValue != nil else {
                throw RPCFailure(code: -32602, message: "Tool arguments must be an object.")
            }
            return await tool(context, arguments: arguments).json
        case (_, .modern):
            throw RPCFailure(code: -32601, message: "Method not found: \(method)", status: 404)
        case (_, .legacy):
            throw RPCFailure(code: -32601, message: "Method not found: \(method)")
        }
    }

    private static var supportedVersions: JSON {
        .array((modernVersions + legacyVersions).map(JSON.string))
    }

    /// Modern requests declare their version and capabilities in `_meta`, and mirror the version,
    /// method and tool name in headers, so intermediaries can route on them; they must agree.
    private static func validateModern(_ method: String, params: JSON, request: HTTPRequest) throws(RPCFailure) {
        let meta = params["_meta"]
        guard let version = meta?["io.modelcontextprotocol/protocolVersion"]?.stringValue,
            meta?["io.modelcontextprotocol/clientCapabilities"]?.objectValue != nil
        else {
            throw RPCFailure(
                code: -32602,
                message:
                    "Requests must declare io.modelcontextprotocol/protocolVersion and io.modelcontextprotocol/clientCapabilities in _meta.",
                status: 400)
        }
        guard modernVersions.contains(version) else {
            throw RPCFailure(
                code: -32022, message: "Unsupported protocol version",
                data: ["supported": supportedVersions, "requested": .string(version)], status: 400)
        }
        guard request.header("mcp-protocol-version") == version else {
            throw RPCFailure(
                code: -32020, message: "Header mismatch: MCP-Protocol-Version must be \(version), as in _meta.",
                status: 400)
        }
        guard request.header("mcp-method") == method else {
            throw RPCFailure(
                code: -32020, message: "Header mismatch: Mcp-Method must be \(method), as in the body.", status: 400)
        }
        if method == "tools/call", decodeHeaderValue(request.header("mcp-name")) != params["name"]?.stringValue {
            throw RPCFailure(
                code: -32020, message: "Header mismatch: Mcp-Name must be the name of the tool called.", status: 400)
        }
    }

    /// Header values that aren't plain ASCII arrive Base64-encoded between `=?base64?` and `?=`.
    private static func decodeHeaderValue(_ value: String?) -> String? {
        guard let value, value.hasPrefix("=?base64?"), value.hasSuffix("?=") else { return value }
        let encoded = value.dropFirst("=?base64?".count).dropLast("?=".count)
        return Data(base64Encoded: String(encoded)).flatMap { String(data: $0, encoding: .utf8) }
    }

    // MARK: - Helpers

    private static func envelope(id: JSON, error: RPCFailure) -> JSON {
        var object: [String: JSON] = ["code": .number(Double(error.code)), "message": .string(error.message)]
        object["data"] = error.data
        return ["jsonrpc": "2.0", "id": id, "error": .object(object)]
    }

    private static func isLoopback(host: String?) -> Bool {
        guard let host else { return false }
        let name = if host.hasPrefix("[") { host.dropFirst().prefix { $0 != "]" } } else { host.prefix { $0 != ":" } }
        return ["127.0.0.1", "localhost", "::1"].contains(name.lowercased())
    }
}

/// A JSON-RPC error, and the HTTP status that carries it. Modern-era validation errors use 4xx;
/// everything else is a normal 200 response.
private struct RPCFailure: Error {
    var code: Int
    var message: String
    var data: JSON?
    var status = 200
}
