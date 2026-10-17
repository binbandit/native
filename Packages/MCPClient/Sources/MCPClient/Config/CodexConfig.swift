import Foundation

/// Codex's MCP configuration: `[mcp_servers.<name>]` tables in `$CODEX_HOME/config.toml`
/// (`~/.codex`), and in a project's `.codex/config.toml` when the project is trusted
/// (`[projects."<path>"] trust_level = "trusted"`). Servers its plugins bring come from
/// `codex mcp list --json` instead (`CodexListing`).
struct CodexConfig {
    var home: URL
    var environment: [String: String]
    var reader: ConfigFileReader

    var userFile: URL {
        let codexHome =
            environment["CODEX_HOME"].map { URL(filePath: $0, directoryHint: .isDirectory) }
            ?? home.appending(path: ".codex", directoryHint: .isDirectory)
        return codexHome.appending(path: "config.toml")
    }

    func read(projects: [URL]) -> AgentMCPConfiguration {
        var problems: [ConfigProblem] = []
        var files = [ConfigFile(url: userFile, role: "User servers", exists: reader.exists(userFile))]
        let user = table(at: userFile, problems: &problems)
        var servers = Self.servers(in: user, scope: .user, source: userFile)

        for project in projects {
            let file = project.appending(path: ".codex/config.toml")
            let exists = reader.exists(file)
            files.append(
                ConfigFile(url: file, role: "Project servers for \(project.lastPathComponent)", exists: exists))
            guard exists else { continue }
            let isTrusted = user?["projects"]?[ProjectPath.key(project)]?["trust_level"]?.stringValue == "trusted"
            servers += Self.servers(in: table(at: file, problems: &problems), scope: .project(project), source: file)
                .map { server in
                    guard !isTrusted, server.status == .enabled else { return server }
                    var server = server
                    server.status = .awaitingApproval
                    server.notes.append("Codex reads a project's own config only once you trust the project.")
                    return server
                }
        }
        return AgentMCPConfiguration(format: .codex, servers: servers, files: files, problems: problems)
    }

    private func table(at url: URL, problems: inout [ConfigProblem]) -> TOMLValue? {
        guard let data = reader.data(at: url) else { return nil }
        do {
            return .table(try TOML.parse(String(decoding: data, as: UTF8.self)))
        } catch {
            problems.append(ConfigProblem(file: url, message: "It isn't valid TOML (\(error))."))
            return nil
        }
    }

    static func servers(in config: TOMLValue?, scope: ConfiguredServer.Scope, source: URL) -> [ConfiguredServer] {
        guard let tables = config?["mcp_servers"]?.tableValue else { return [] }
        return tables.keys.sorted().compactMap { name in
            tables[name].flatMap { server(named: name, $0, scope: scope, source: source) }
        }
    }

    /// One `[mcp_servers.<name>]` table: `command`/`args`/`env`/`env_vars`/`cwd` for a local server,
    /// `url`/`http_headers`/`env_http_headers`/`bearer_token_env_var` for a remote one, and
    /// `enabled`, `enabled_tools` and `disabled_tools` for either.
    static func server(
        named name: String, _ table: TOMLValue, scope: ConfiguredServer.Scope, source: URL
    ) -> ConfiguredServer? {
        let strings = { (key: String) in table[key]?.arrayValue?.compactMap(\.scalarText) ?? [] }
        let dictionary = { (key: String) in (table[key]?.tableValue ?? [:]).compactMapValues(\.scalarText) }
        let transport: MCPTransport
        if let command = table["command"]?.stringValue {
            transport = .stdio(
                command: command, arguments: strings("args"), environment: dictionary("env"),
                workingDirectory: table["cwd"]?.stringValue)
        } else if let text = table["url"]?.stringValue, let url = URL(string: text) {
            transport = .http(url: url, headers: dictionary("http_headers"))
        } else {
            return nil
        }
        // `env_vars` lists names to pass through, as strings or `{ name = "…" }` tables.
        let passThrough = (table["env_vars"]?.arrayValue ?? []).compactMap { $0.stringValue ?? $0["name"]?.stringValue }
        let bearer = table["bearer_token_env_var"]?.stringValue
        let headerVariables = dictionary("env_http_headers")
        var notes: [String] = []
        if let bearer { notes.append("Bearer token from $\(bearer)") }
        if !passThrough.isEmpty {
            notes.append("Passes through \(passThrough.map { "$" + $0 }.joined(separator: ", "))")
        }
        if !strings("enabled_tools").isEmpty {
            notes.append("Only tools: \(strings("enabled_tools").joined(separator: ", "))")
        }
        if !strings("disabled_tools").isEmpty {
            notes.append("Without tools: \(strings("disabled_tools").joined(separator: ", "))")
        }
        return ConfiguredServer(
            server: MCPServerConfig(name: name, transport: transport),
            format: .codex,
            scope: scope,
            source: source,
            status: table["enabled"]?.boolValue == false ? .disabled : .enabled,
            resolution: .codex(passThrough: passThrough, bearerTokenVariable: bearer, headerVariables: headerVariables),
            notes: notes
        )
    }
}

/// What `codex mcp list --json` reports: every server Codex would load, its plugins' included, and
/// whether it's signed in. It complements the files, which don't say what plugins add.
public struct CodexListing: Hashable, Sendable {
    public struct Server: Hashable, Sendable {
        public var name: String
        public var isEnabled: Bool
        /// `unsupported`, `not_logged_in`, `bearer_token` or `oauth`.
        public var authStatus: String?
        public var transport: MCPTransport

        public var needsSignIn: Bool { authStatus == "not_logged_in" }
    }

    public var servers: [Server]

    public init(servers: [Server]) {
        self.servers = servers
    }

    public static func decode(_ data: Data) throws -> CodexListing {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let entries = try decoder.decode([Entry].self, from: data)
        return CodexListing(
            servers: entries.compactMap { entry in
                let transport: MCPTransport
                switch (entry.transport.command, entry.transport.url.flatMap(URL.init(string:))) {
                case (let command?, _):
                    transport = .stdio(
                        command: command, arguments: entry.transport.args ?? [],
                        environment: entry.transport.env ?? [:], workingDirectory: entry.transport.cwd)
                case (nil, let url?):
                    transport = .http(url: url, headers: entry.transport.httpHeaders ?? [:])
                default:
                    return nil
                }
                return Server(
                    name: entry.name, isEnabled: entry.enabled ?? true, authStatus: entry.authStatus,
                    transport: transport)
            })
    }

    private struct Entry: Decodable {
        struct Transport: Decodable {
            var command: String?
            var args: [String]?
            var env: [String: String]?
            var cwd: String?
            var url: String?
            var httpHeaders: [String: String]?
        }

        var name: String
        var enabled: Bool?
        var authStatus: String?
        var transport: Transport
    }
}

extension AgentMCPConfiguration {
    /// Adds the servers Codex lists but its files don't hold (its plugins'), and takes the listing's
    /// word on what's enabled and what needs signing in.
    public func merging(_ listing: CodexListing) -> AgentMCPConfiguration {
        var merged = self
        let listed = Dictionary(listing.servers.map { ($0.name, $0) }, uniquingKeysWith: { first, _ in first })
        for index in merged.servers.indices where merged.servers[index].scope == .user {
            guard let server = listed[merged.servers[index].name] else { continue }
            if !server.isEnabled { merged.servers[index].status = .disabled }
        }
        let known = Set(merged.servers.map(\.name))
        for server in listing.servers where !known.contains(server.name) {
            merged.servers.append(
                ConfiguredServer(
                    server: MCPServerConfig(name: server.name, transport: server.transport),
                    format: .codex,
                    scope: .plugin(Self.pluginName(of: server) ?? "Codex"),
                    source: Self.pluginRoot(of: server) ?? merged.files.first?.url ?? URL(filePath: "/"),
                    status: server.isEnabled ? .enabled : .disabled
                ))
        }
        merged.signInRequired = Set(listing.servers.filter(\.needsSignIn).map(\.name))
        return merged
    }

    /// Plugins run from `…/plugins/cache/<marketplace>/<plugin>/<version>`.
    private static func pluginName(of server: CodexListing.Server) -> String? {
        guard let root = pluginRoot(of: server) else { return nil }
        let parts = root.pathComponents
        guard let cache = parts.lastIndex(of: "cache"), cache + 2 < parts.count else { return nil }
        return parts[cache + 2]
    }

    private static func pluginRoot(of server: CodexListing.Server) -> URL? {
        guard case .stdio(_, _, _, let directory?) = server.transport, directory.contains("/plugins/cache/") else {
            return nil
        }
        return URL(filePath: directory, directoryHint: .isDirectory).standardizedFileURL
    }
}
