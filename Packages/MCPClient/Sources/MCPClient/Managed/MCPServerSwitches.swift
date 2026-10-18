import Foundation

/// Native's on/off switch for every MCP server, wherever it's defined (Native's own, or an agent's
/// configuration), for all projects and per project. Servers are keyed by `MCPEndpointIdentity.key`,
/// so one switch covers the same server however each agent names it. A server without a switch is
/// on; a project's switch beats the global one.
public struct MCPServerSwitches: Hashable, Sendable, Codable {
    public enum Mode: String, Hashable, Sendable, Codable {
        case on
        case off
        // Planned: `scripted`, the server reachable only through Native's `run_script` tool, so its
        // tool schemas don't load into every session (docs/script-runtime.md, "Code mode").
    }

    public private(set) var global: [String: Mode]
    /// By project path (`ProjectPath.key`), then server key.
    public private(set) var projects: [String: [String: Mode]]

    public init(global: [String: Mode] = [:], projects: [String: [String: Mode]] = [:]) {
        self.global = global
        self.projects = projects
    }

    /// The mode in `directory`: the switch of the innermost project containing it, else the
    /// global one, else on.
    public func mode(of server: String, in directory: URL?) -> Mode {
        if let directory, let project = project(containing: directory), let mode = projects[project]?[server] {
            return mode
        }
        return global[server] ?? .on
    }

    /// The switch set exactly at `project` (or globally when nil), without falling back.
    public func explicitMode(of server: String, in project: URL?) -> Mode? {
        guard let project else { return global[server] }
        return projects[ProjectPath.key(project)]?[server]
    }

    /// Sets a switch; nil removes it, so the server follows the global switch (or is on).
    public mutating func set(_ mode: Mode?, for server: String, in project: URL?) {
        guard let project else {
            global[server] = mode
            return
        }
        let path = ProjectPath.key(project)
        projects[path, default: [:]][server] = mode
        if projects[path]?.isEmpty == true { projects[path] = nil }
    }

    /// Servers off everywhere, whatever the project.
    public var globallyOff: Set<String> {
        Set(global.filter { $0.value == .off }.keys)
    }

    /// Whether any project turns `server` to a different mode than the global switch.
    public func hasProjectOverrides(for server: String) -> Bool {
        projects.values.contains { $0[server] != nil }
    }

    private func project(containing directory: URL) -> String? {
        let path = ProjectPath.key(directory)
        return projects.keys
            .filter { path == $0 || path.hasPrefix($0 == "/" ? $0 : $0 + "/") }
            .max { $0.count < $1.count }
    }
}

extension MCPEndpointIdentity {
    /// A stable string for storing switches.
    public var key: String {
        switch self {
        case .command(let command, let arguments): "command:" + ShellQuoting.commandLine([command] + arguments)
        case .url(let url): "url:" + url
        }
    }
}
