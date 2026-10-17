import Foundation

/// An MCP server as a client would connect to it: a name and a transport.
public struct MCPServerConfig: Hashable, Sendable {
    public var name: String
    public var transport: MCPTransport

    public init(name: String, transport: MCPTransport) {
        self.name = name
        self.transport = transport
    }

    /// What makes two configurations the same server whatever they're called.
    public var endpoint: MCPEndpointIdentity {
        transport.endpoint
    }
}

/// How a client reaches an MCP server. Environment and header values are often secrets: show
/// their names (`secretNames`), never the values.
public enum MCPTransport: Hashable, Sendable {
    /// A local server the client launches, speaking JSON-RPC over stdin and stdout.
    case stdio(
        command: String, arguments: [String] = [], environment: [String: String] = [:], workingDirectory: String? = nil)
    /// A remote server over Streamable HTTP.
    case http(url: URL, headers: [String: String] = [:])
    /// A remote server over the HTTP+SSE transport that Streamable HTTP replaced (2024-11-05).
    case sse(url: URL, headers: [String: String] = [:])

    public enum Kind: String, Hashable, Sendable, Codable, CaseIterable {
        case stdio, http, sse

        public var displayName: String {
            switch self {
            case .stdio: "Local"
            case .http: "HTTP"
            case .sse: "SSE"
            }
        }
    }

    public var kind: Kind {
        switch self {
        case .stdio: .stdio
        case .http: .http
        case .sse: .sse
        }
    }

    public var url: URL? {
        switch self {
        case .stdio: nil
        case .http(let url, _), .sse(let url, _): url
        }
    }

    /// The environment variables or headers it sets, by name only.
    public var secretNames: [String] {
        switch self {
        case .stdio(_, _, let environment, _): environment.keys.sorted()
        case .http(_, let headers), .sse(_, let headers): headers.keys.sorted()
        }
    }

    /// The command line, quoted the way a shell would need it, or the URL.
    public var summary: String {
        switch self {
        case .stdio(let command, let arguments, _, _): ShellQuoting.commandLine([command] + arguments)
        case .http(let url, _), .sse(let url, _): url.absoluteString
        }
    }

    public var endpoint: MCPEndpointIdentity {
        switch self {
        case .stdio(let command, let arguments, _, _):
            .command(MCPEndpointIdentity.normalized(command: command), arguments)
        case .http(let url, _), .sse(let url, _):
            .url(MCPEndpointIdentity.normalized(url: url))
        }
    }
}

/// A server's identity for spotting duplicates: the same command line, or the same URL, is the
/// same server even when two configurations name it differently.
public enum MCPEndpointIdentity: Hashable, Sendable {
    case command(String, [String])
    case url(String)

    /// `npx` and `/opt/homebrew/bin/npx` run the same thing.
    static func normalized(command: String) -> String {
        command.contains("/") ? URL(filePath: command).lastPathComponent : command
    }

    /// Scheme and host are case-insensitive, and a trailing slash doesn't make a new endpoint.
    static func normalized(url: URL) -> String {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return url.absoluteString
        }
        components.scheme = components.scheme?.lowercased()
        components.host = components.host?.lowercased()
        while components.path.count > 1, components.path.hasSuffix("/") {
            components.path.removeLast()
        }
        components.fragment = nil
        return components.string ?? url.absoluteString
    }
}

/// Which transports an agent can be handed besides stdio, which every agent supports.
public struct MCPTransportSupport: Hashable, Sendable {
    public var http: Bool
    public var sse: Bool

    public init(http: Bool, sse: Bool) {
        self.http = http
        self.sse = sse
    }

    public func supports(_ kind: MCPTransport.Kind) -> Bool {
        switch kind {
        case .stdio: true
        case .http: http
        case .sse: sse
        }
    }
}
