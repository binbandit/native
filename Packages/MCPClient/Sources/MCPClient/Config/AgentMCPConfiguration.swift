import Foundation

/// Everything one agent's own configuration says about MCP servers, across its scopes.
public struct AgentMCPConfiguration: Hashable, Sendable {
    public var format: AgentConfigFormat
    /// Every entry in every scope read. Project entries carry the status they have in their project.
    public var servers: [ConfiguredServer]
    /// The files that hold the configuration, whether or not they exist yet.
    public var files: [ConfigFile]
    /// Files that exist but couldn't be read.
    public var problems: [ConfigProblem]
    /// Remote connectors that come with the user's account rather than a file (claude.ai's).
    public var accountConnectors: [String]
    /// Server names the user turned off in a project, keyed by project path.
    public var disabledInProject: [String: Set<String>]
    /// An administrator's configuration is in force; the agent loads only its servers.
    public var isManagedOnly: Bool
    /// Servers the agent itself says need the user to sign in (Codex's listing does).
    public var signInRequired: Set<String> = []

    public init(
        format: AgentConfigFormat, servers: [ConfiguredServer] = [], files: [ConfigFile] = [],
        problems: [ConfigProblem] = [],
        accountConnectors: [String] = [], disabledInProject: [String: Set<String>] = [:], isManagedOnly: Bool = false
    ) {
        self.format = format
        self.servers = servers
        self.files = files
        self.problems = problems
        self.accountConnectors = accountConnectors
        self.disabledInProject = disabledInProject
        self.isManagedOnly = isManagedOnly
    }

    /// What the agent loads in `project` (or outside any project): one entry per name, the scope
    /// that wins for each, and its status there.
    public func effective(in project: URL?) -> [ConfiguredServer] {
        let projectPath = project.map(ProjectPath.key)
        let candidates = servers.filter { entry in
            if isManagedOnly { return entry.scope == .managed }
            guard let scoped = entry.scope.project else { return true }
            return ProjectPath.key(scoped) == projectPath
        }
        let ranked = candidates.enumerated().sorted { lhs, rhs in
            let (left, right) = (precedence(of: lhs.element.scope), precedence(of: rhs.element.scope))
            return left == right ? lhs.offset < rhs.offset : left < right
        }
        var seen: Set<String> = []
        var result: [ConfiguredServer] = []
        let disabled = projectPath.flatMap { disabledInProject[$0] } ?? []
        for (_, entry) in ranked where seen.insert(entry.name).inserted {
            var entry = entry
            if entry.status == .enabled, disabled.contains(entry.name) {
                entry.status = .disabledInProject
            }
            result.append(entry)
        }
        return result
    }

    /// Lower wins. Claude Code: local, then project, then user. Codex and Cursor: project over user.
    private func precedence(of scope: ConfiguredServer.Scope) -> Int {
        switch scope {
        case .managed: 0
        case .local: 1
        case .project: 2
        case .user: 3
        case .plugin: 4
        }
    }
}

/// A configuration file and what it holds for the agent.
public struct ConfigFile: Hashable, Sendable, Identifiable {
    public var url: URL
    /// Such as "User and local servers" or "Project servers for app".
    public var role: String
    public var exists: Bool

    public init(url: URL, role: String, exists: Bool) {
        self.url = url
        self.role = role
        self.exists = exists
    }

    public var id: URL { url }
}

public struct ConfigProblem: Hashable, Sendable, Identifiable {
    public var file: URL
    public var message: String

    public init(file: URL, message: String) {
        self.file = file
        self.message = message
    }

    public var id: URL { file }
}

/// Projects are compared by their standardized path, without a trailing slash.
public enum ProjectPath {
    public static func key(_ url: URL) -> String {
        var path = url.standardizedFileURL.path(percentEncoded: false)
        while path.count > 1, path.hasSuffix("/") {
            path.removeLast()
        }
        return path
    }

    public static func url(_ path: String) -> URL {
        URL(filePath: key(URL(filePath: path)), directoryHint: .isDirectory)
    }
}
