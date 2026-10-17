import Foundation

/// Cursor's MCP configuration: `~/.cursor/mcp.json` for every project and `<project>/.cursor/mcp.json`
/// for one, the second winning on a shared name. Values may use `${env:VAR}`, `${userHome}` and
/// `${workspaceFolder}`.
struct CursorConfig {
    var home: URL

    func read(projects: [URL]) -> AgentMCPConfiguration {
        var problems: [ConfigProblem] = []
        let userFile = home.appending(path: ".cursor/mcp.json")
        var files = [ConfigFile(url: userFile, role: "User servers", exists: ConfigFileReader.exists(userFile))]
        var servers = servers(in: userFile, scope: .user, problems: &problems)
        for project in projects {
            let file = project.appending(path: ".cursor/mcp.json")
            files.append(ConfigFile(url: file, role: "Project servers for \(project.lastPathComponent)", exists: ConfigFileReader.exists(file)))
            servers += self.servers(in: file, scope: .project(project), problems: &problems)
        }
        return AgentMCPConfiguration(format: .cursor, servers: servers, files: files, problems: problems)
    }

    private func servers(in file: URL, scope: ConfiguredServer.Scope, problems: inout [ConfigProblem]) -> [ConfiguredServer] {
        let json = ConfigFileReader.json(at: file, problems: &problems)
        return ServerMap.servers(in: json?["mcpServers"], file: file, problems: &problems).map { server in
            var entry = ConfiguredServer(server: server, format: .cursor, scope: scope, source: file, resolution: .cursor)
            // Cursor works out which of the two HTTP transports a URL speaks; so does the probe.
            if case .http = server.transport {
                entry.notes.append("Cursor picks Streamable HTTP or SSE for this URL itself.")
            }
            return entry
        }
    }
}

/// Reads agents' own MCP configuration files. Nothing here writes them: changes go through the
/// agents' CLIs (`AgentCLICommand`).
public struct AgentConfigReader: Sendable {
    public var home: URL
    /// The user's environment, for `CLAUDE_CONFIG_DIR` and `CODEX_HOME`.
    public var environment: [String: String]
    /// Where Claude Code's administrator configuration would be; replaceable for tests.
    public var claudeManagedFile: URL

    public init(
        home: URL = FileManager.default.homeDirectoryForCurrentUser,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        claudeManagedFile: URL = URL(filePath: "/Library/Application Support/ClaudeCode/managed-mcp.json")
    ) {
        self.home = home
        self.environment = environment
        self.claudeManagedFile = claudeManagedFile
    }

    /// The format's servers at user scope and in each of `projects`.
    public func read(_ format: AgentConfigFormat, projects: [URL]) -> AgentMCPConfiguration {
        let projects = projects.map { ProjectPath.url(ProjectPath.key($0)) }
        return switch format {
        case .claudeCode: ClaudeCodeConfig(home: home, environment: environment, managedFile: claudeManagedFile).read(projects: projects)
        case .codex: CodexConfig(home: home, environment: environment).read(projects: projects)
        case .cursor: CursorConfig(home: home).read(projects: projects)
        }
    }
}
