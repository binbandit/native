import Exec
import Foundation
import MCP
import Synchronization

/// A live connection to one MCP server: initialized, its tools listed, and able to call them. The
/// "Scripted" switch state builds on it: Native holds the session and exposes the server's tools
/// to `run_script`, so their schemas don't load into the agent's context. Probes never call tools;
/// this is the one place that does, and only when asked.
public final class MCPSession: Sendable {
    /// A tool with the schemas a caller needs to use it.
    public struct Tool: Hashable, Sendable, Identifiable {
        public var info: MCPToolInfo
        public var inputSchema: JSON?
        public var outputSchema: JSON?

        public var id: String { info.name }
    }

    public let server: MCPServerInfo
    public let tools: [Tool]
    public let transportKind: MCPTransport.Kind
    private let transport: any MCPClientTransport
    private let ids = RequestIDs()

    /// Connects, initializes and lists the tools, like a probe, but stays connected.
    public static func connect(
        _ config: MCPServerConfig, environment: [String: String], directory: String?,
        clientVersion: String = "0", launcher: any StdioLauncher
    ) async throws(MCPSessionError) -> MCPSession {
        let transport: any MCPClientTransport
        let kind: MCPTransport.Kind
        do throws(ProbeError) {
            switch config.transport {
            case .stdio(let command, let arguments, let variables, let workingDirectory):
                transport = try StdioTransport(
                    Command(
                        command, arguments, in: MCPProbe.directory(workingDirectory, relativeTo: directory),
                        environment: environment.merging(variables) { $1 }),
                    launcher: launcher)
                kind = .stdio
            case .http(let url, let headers):
                transport = StreamableHTTPTransport(url: url, headers: headers, session: MCPSession.urlSession())
                kind = .http
            case .sse(let url, let headers):
                transport = try await LegacySSETransport.connect(
                    url: url, headers: headers, session: MCPSession.urlSession())
                kind = .sse
            }
            let outcome = try await MCPHandshake(
                clientName: "native", clientTitle: "Native", clientVersion: clientVersion
            )
            .run(on: transport)
            let tools = outcome.tools.map { info in
                let definition = outcome.definitions[info.name]
                return Tool(
                    info: info, inputSchema: definition?["inputSchema"], outputSchema: definition?["outputSchema"])
            }
            return MCPSession(server: outcome.server, tools: tools, transportKind: kind, transport: transport)
        } catch {
            throw MCPSessionError(error)
        }
    }

    private init(
        server: MCPServerInfo, tools: [Tool], transportKind: MCPTransport.Kind, transport: any MCPClientTransport
    ) {
        self.server = server
        self.tools = tools
        self.transportKind = transportKind
        self.transport = transport
    }

    /// Calls a tool with an arguments object and returns the server's result (`content`,
    /// `structuredContent`, `isError`) as it sent it.
    public func call(_ tool: String, arguments: JSON) async throws(MCPSessionError) -> JSON {
        do throws(ProbeError) {
            return try await transport.request(
                "tools/call", params: ["name": .string(tool), "arguments": arguments], id: ids.next())
        } catch {
            throw MCPSessionError(error)
        }
    }

    public func close() async {
        await transport.close()
    }

    private static func urlSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpShouldSetCookies = false
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        return URLSession(configuration: configuration)
    }
}

/// Why a session couldn't connect or a call failed, in words for the user.
public struct MCPSessionError: Error, Hashable, Sendable, LocalizedError {
    public var message: String
    /// Set when the server wants credentials.
    public var authChallenge: MCPAuthChallenge?

    init(_ error: ProbeError) {
        switch error {
        case .failed(let failure): message = failure.message
        case .needsAuth(let challenge):
            message = "The server asks you to sign in (HTTP \(challenge.statusCode))."
            authChallenge = challenge
        case .notStreamableHTTP(let status): message = "The server answered HTTP \(status)."
        case .cancelled: message = "Cancelled."
        }
    }

    public var errorDescription: String? { message }
}

/// JSON-RPC ids after the handshake's (which uses 1 and the pages of `tools/list` after it).
private final class RequestIDs: Sendable {
    private let counter = Mutex(1_000)

    func next() -> Int {
        counter.withLock { value in
            value += 1
            return value
        }
    }
}
