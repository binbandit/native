import Foundation
import MCP

/// Sends JSON-RPC requests to a server and returns their results. One request at a time.
protocol MCPClientTransport: Sendable {
    func request(_ method: String, params: JSON, id: Int) async throws(ProbeError) -> JSON
    func notify(_ method: String, params: JSON) async throws(ProbeError)
    func close() async
}

/// Errors on the way to a report, mapped to its status at the end.
enum ProbeError: Error {
    case failed(MCPProbeFailure)
    case needsAuth(MCPAuthChallenge)
    /// The URL doesn't take Streamable HTTP posts; it may speak the older SSE transport.
    case notStreamableHTTP(status: Int)
    case cancelled

    static func failure(_ stage: MCPProbeFailure.Stage, _ message: String, exitStatus: Int32? = nil) -> ProbeError {
        .failed(MCPProbeFailure(stage: stage, message: message, exitStatus: exitStatus))
    }
}

/// The client side of MCP's lifecycle, as far as listing tools: `initialize`, then
/// `notifications/initialized`, then `tools/list` until the last page. Tools are never called.
struct MCPHandshake {
    /// Newest first; servers answer with the one they speak.
    static let protocolVersion = "2025-11-25"
    /// A server that keeps paging past this is cut off rather than looped on.
    static let pageLimit = 50

    var clientName: String
    var clientTitle: String
    var clientVersion: String

    struct Outcome {
        var server: MCPServerInfo
        var tools: [MCPToolInfo]
        var toolDefinitionBytes: Int
    }

    func run(on transport: some MCPClientTransport) async throws(ProbeError) -> Outcome {
        let initialize = try await transport.request(
            "initialize",
            params: [
                "protocolVersion": .string(Self.protocolVersion),
                // Native answers none of the server's requests (sampling, roots, elicitation).
                "capabilities": [:],
                "clientInfo": [
                    "name": .string(clientName), "title": .string(clientTitle), "version": .string(clientVersion),
                ],
            ], id: 1)
        guard let version = initialize["protocolVersion"]?.stringValue else {
            throw .failure(.initialize, "The server's answer to initialize has no protocol version.")
        }
        let info = initialize["serverInfo"]
        let server = MCPServerInfo(
            name: info?["name"]?.stringValue ?? "",
            title: info?["title"]?.stringValue,
            version: info?["version"]?.stringValue,
            protocolVersion: version,
            instructions: initialize["instructions"]?.stringValue
        )
        try await transport.notify("notifications/initialized", params: [:])

        // A server without the tools capability has none to list.
        guard initialize["capabilities"]?["tools"] != nil else {
            return Outcome(server: server, tools: [], toolDefinitionBytes: 0)
        }
        var tools: [MCPToolInfo] = []
        var bytes = 0
        var cursor: String?
        for page in 0..<Self.pageLimit {
            var params: [String: JSON] = [:]
            params["cursor"] = cursor.map(JSON.string)
            let result: JSON
            do {
                result = try await transport.request("tools/list", params: .object(params), id: 2 + page)
            } catch .failed(let failure) {
                throw .failure(.listTools, failure.message, exitStatus: failure.exitStatus)
            }
            for definition in result["tools"]?.arrayValue ?? [] {
                let size = Self.encodedSize(of: definition)
                bytes += size
                if var tool = Self.tool(from: definition) {
                    tool.definitionBytes = size
                    tools.append(tool)
                }
            }
            cursor = result["nextCursor"]?.stringValue
            if cursor == nil { break }
        }
        return Outcome(server: server, tools: tools, toolDefinitionBytes: bytes)
    }

    static func tool(from definition: JSON) -> MCPToolInfo? {
        guard let name = definition["name"]?.stringValue else { return nil }
        let schema = definition["inputSchema"]
        let required = schema?["required"]?.stringArray ?? []
        let properties = (schema?["properties"]?.objectValue ?? [:]).keys.sorted()
        let annotations = definition["annotations"]
        return MCPToolInfo(
            name: name,
            title: definition["title"]?.stringValue ?? annotations?["title"]?.stringValue,
            description: definition["description"]?.stringValue,
            parameters: required.filter(properties.contains) + properties.filter { !required.contains($0) },
            isReadOnly: annotations?["readOnlyHint"]?.boolValue,
            isDestructive: annotations?["destructiveHint"]?.boolValue
        )
    }

    private static func encodedSize(of value: JSON) -> Int {
        (try? JSONEncoder().encode(value).count) ?? 0
    }
}

/// JSON-RPC 2.0 framing.
enum JSONRPC {
    static func request(_ method: String, params: JSON, id: Int) -> Data {
        encode(["jsonrpc": "2.0", "id": .number(Double(id)), "method": .string(method), "params": params])
    }

    static func notification(_ method: String, params: JSON) -> Data {
        encode(["jsonrpc": "2.0", "method": .string(method), "params": params])
    }

    /// Native's reply to a request from the server: `ping` gets its empty result; everything else
    /// is a client feature the probe doesn't offer.
    static func reply(to method: String, id: JSON) -> Data {
        guard method != "ping" else { return encode(["jsonrpc": "2.0", "id": id, "result": [:]]) }
        return encode([
            "jsonrpc": "2.0", "id": id,
            "error": ["code": -32601, "message": .string("Native's probe doesn't support \(method).")],
        ])
    }

    static func encode(_ message: JSON) -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .withoutEscapingSlashes
        return (try? encoder.encode(message)) ?? Data()
    }

    enum Message {
        /// The answer to request `id`: its result, or the error it failed with.
        case response(id: Int, Result<JSON, RPCFailure>)
        /// The server asking the client something, such as `ping` or `roots/list`.
        case request(id: JSON, method: String)
        case notification
    }

    struct RPCFailure: Error {
        let code: Int
        let message: String
    }

    static func decode(_ data: Data) -> Message? {
        guard let message = try? JSONDecoder().decode(JSON.self, from: data), case .object(let fields) = message else {
            return nil
        }
        if let method = fields["method"]?.stringValue {
            if let id = fields["id"], id != .null { return .request(id: id, method: method) }
            return .notification
        }
        guard case .number(let number)? = fields["id"] else { return nil }
        let id = Int(number)
        if let error = fields["error"] {
            let code = error["code"].flatMap { if case .number(let code) = $0 { Int(code) } else { nil } } ?? 0
            return .response(
                id: id, .failure(RPCFailure(code: code, message: error["message"]?.stringValue ?? "Unknown error.")))
        }
        return .response(id: id, .success(fields["result"] ?? [:]))
    }
}
