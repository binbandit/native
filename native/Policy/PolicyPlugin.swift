import ACP
import NativePolicy

/// The organization's policy for sessions, applied like any plugin's but never switched off: skills
/// it blocks are turned off for every session through each agent's own mechanism
/// (`SessionPolicyTranslator`), and servers it requires are added. Blocked MCP servers are handled
/// where Native knows they exist: `PluginRegistry` filters the servers Native hands over, and
/// `MCPLibrary` turns off agents' own configured ones. Naming a server an agent doesn't define
/// would break that agent's configuration (Codex rejects a server with no command).
struct PolicyPlugin: NativePlugin {
    let policy: NativePolicy

    let manifest = PluginManifest(
        id: "native.policy",
        name: "Organization Policy",
        description: "Applies your organization's managed settings to every session."
    )

    func sessionPolicy(for session: SessionContext) -> SessionPolicy {
        launchPolicy(for: session.agent)
    }

    func launchPolicy(for agent: AgentDefinition.ID) -> SessionPolicy {
        SessionPolicy(disabledSkills: policy.blockedSkills.map { .init(name: $0, path: nil, scope: .allProjects) })
    }

    func mcpServers(for session: SessionContext) -> [MCPServer] {
        policy.mcp.required.map(\.server)
    }
}

extension RequiredMCPServer {
    var server: MCPServer {
        switch transport {
        case .stdio(let command, let arguments, let environment):
            .stdio(name: name, command: command, arguments: arguments, environment: environment)
        case .http(let url, let headers):
            .http(name: name, url: url, headers: headers)
        }
    }
}

extension MCPServer {
    var policyName: String {
        switch self {
        case .stdio(let name, _, _, _), .http(let name, _, _): name
        }
    }

    /// The command line, for `command:` patterns; nil for remote servers.
    var policyCommandLine: String? {
        switch self {
        case .stdio(_, let command, let arguments, _): ([command] + arguments).joined(separator: " ")
        case .http: nil
        }
    }
}
