import Foundation
import MCP

/// Claude Code's MCP configuration, read the way it loads it:
///
/// - user scope: `mcpServers` in `~/.claude.json`
/// - local scope: `projects["<path>"].mcpServers` in the same file, private to one project
/// - project scope: `<project>/.mcp.json`, loaded once the user approves it (`enabledMcpjsonServers`,
///   `disabledMcpjsonServers` or `enableAllProjectMcpServers`, in `~/.claude.json` or a settings file)
/// - plugins: enabled plugins' `.mcp.json` or `plugin.json` `mcpServers`, named `plugin:<plugin>:<name>`
/// - managed: `managed-mcp.json`, which replaces everything else when present
///
/// `projects["<path>"].disabledMcpServers` turns servers off in one project (`/mcp disable`).
/// `CLAUDE_CONFIG_DIR` moves both `~/.claude` and `.claude.json`.
struct ClaudeCodeConfig {
    var home: URL
    var environment: [String: String]
    var managedFile: URL
    var reader: ConfigFileReader

    private var configDirectory: URL {
        environment["CLAUDE_CONFIG_DIR"].map { URL(filePath: $0, directoryHint: .isDirectory) }
            ?? home.appending(path: ".claude", directoryHint: .isDirectory)
    }

    private var globalFile: URL {
        environment["CLAUDE_CONFIG_DIR"].map {
            URL(filePath: $0, directoryHint: .isDirectory).appending(path: ".claude.json")
        } ?? home.appending(path: ".claude.json")
    }

    func read(projects: [URL]) -> AgentMCPConfiguration {
        var problems: [ConfigProblem] = []
        var servers: [ConfiguredServer] = []
        var files = [
            ConfigFile(url: globalFile, role: "User and local servers", scope: .user, exists: reader.exists(globalFile))
        ]
        let global = reader.json(at: globalFile, problems: &problems)
        let userSettings = reader.json(at: configDirectory.appending(path: "settings.json"), problems: &problems)

        servers += ServerMap.servers(in: global?["mcpServers"], file: globalFile, problems: &problems).map {
            entry($0, scope: .user, source: globalFile)
        }

        var disabledInProject: [String: Set<String>] = [:]
        for project in projects {
            let key = ProjectPath.key(project)
            let projectEntry = global?["projects"]?[key]
            servers += ServerMap.servers(in: projectEntry?["mcpServers"], file: globalFile, problems: &problems).map {
                entry($0, scope: .local(project), source: globalFile)
            }
            disabledInProject[key] = Set(projectEntry?["disabledMcpServers"]?.stringArray ?? [])

            let mcpJSON = project.appending(path: ".mcp.json")
            let exists = reader.exists(mcpJSON)
            files.append(
                ConfigFile(
                    url: mcpJSON, role: "Project servers for \(project.lastPathComponent)", scope: .project(project),
                    exists: exists))
            guard exists else { continue }
            let settings =
                [projectEntry, userSettings]
                + [".claude/settings.json", ".claude/settings.local.json"].map {
                    reader.json(at: project.appending(path: $0), problems: &problems)
                }
            let approval = ProjectApproval(settings.compactMap(\.self))
            let file = reader.json(at: mcpJSON, problems: &problems)
            servers += ServerMap.servers(in: file?["mcpServers"], file: mcpJSON, problems: &problems).map { server in
                var configured = entry(server, scope: .project(project), source: mcpJSON)
                configured.status = approval.status(of: server.name)
                if configured.status == .awaitingApproval {
                    configured.notes.append(
                        "Claude Code asks before loading servers from .mcp.json; run claude in the project to approve it."
                    )
                }
                return configured
            }
        }

        let (pluginServers, pluginFiles) = readPlugins(settings: userSettings, problems: &problems)
        servers += pluginServers
        files += pluginFiles

        var isManagedOnly = false
        if reader.exists(managedFile) {
            isManagedOnly = true
            files.append(ConfigFile(url: managedFile, role: "Managed servers", scope: .managed, exists: true))
            let managed = reader.json(at: managedFile, problems: &problems)
            servers += ServerMap.servers(in: managed?["mcpServers"], file: managedFile, problems: &problems).map {
                entry($0, scope: .managed, source: managedFile)
            }
        }

        return AgentMCPConfiguration(
            format: .claudeCode,
            servers: servers,
            files: files,
            problems: problems,
            accountConnectors: global?["claudeAiMcpEverConnected"]?.stringArray ?? [],
            disabledInProject: disabledInProject,
            isManagedOnly: isManagedOnly
        )
    }

    private func entry(_ server: MCPServerConfig, scope: ConfiguredServer.Scope, source: URL) -> ConfiguredServer {
        ConfiguredServer(server: server, format: .claudeCode, scope: scope, source: source, resolution: .claudeCode)
    }

    // MARK: - Plugins

    /// Servers of the plugins `enabledPlugins` turns on, from where `installed_plugins.json` put them.
    private func readPlugins(settings: JSON?, problems: inout [ConfigProblem]) -> ([ConfiguredServer], [ConfigFile]) {
        let enabled = (settings?["enabledPlugins"]?.objectValue ?? [:]).filter { $0.value.boolValue == true }.keys
            .sorted()
        guard !enabled.isEmpty else { return ([], []) }
        let installed = reader.json(
            at: configDirectory.appending(path: "plugins/installed_plugins.json"), problems: &problems)
        var servers: [ConfiguredServer] = []
        var files: [ConfigFile] = []
        for id in enabled {
            guard
                let path = installed?["plugins"]?[id]?.arrayValue?.lazy.compactMap({ $0["installPath"]?.stringValue })
                    .first
            else { continue }
            let root = URL(filePath: path, directoryHint: .isDirectory)
            let plugin = String(id.prefix { $0 != "@" })
            for (file, map) in pluginServerMaps(root: root, problems: &problems) {
                files.append(
                    ConfigFile(url: file, role: "Servers of the \(plugin) plugin", scope: .plugin(plugin), exists: true)
                )
                servers += ServerMap.servers(in: map, file: file, problems: &problems).map { server in
                    var server = server
                    server.name = "plugin:\(plugin):\(server.name)"
                    // Claude Code fills in the plugin's folder itself, before any other variable.
                    let rootPath = ProjectPath.key(root)
                    server.transport = server.transport.mapValues {
                        $0.replacingOccurrences(of: "${CLAUDE_PLUGIN_ROOT}", with: rootPath)
                    }
                    return ConfiguredServer(
                        server: server, format: .claudeCode, scope: .plugin(plugin), source: file,
                        resolution: .claudeCode)
                }
            }
        }
        return (servers, files)
    }

    /// A plugin declares servers in `.mcp.json` at its root, or in `plugin.json` as a map or a path
    /// (or list of paths) to such files.
    private func pluginServerMaps(root: URL, problems: inout [ConfigProblem]) -> [(URL, JSON)] {
        var maps: [(URL, JSON)] = []
        let manifestURL = root.appending(path: ".claude-plugin/plugin.json")
        let declared = reader.json(at: manifestURL, problems: &problems)?["mcpServers"]
        var paths: [String] = []
        switch declared {
        case .object(let object)?:
            maps.append((manifestURL, .object(object)))
        case .string(let path)?:
            paths.append(path)
        case .array(let items)?:
            paths += items.compactMap(\.stringValue)
        default:
            paths.append(".mcp.json")
        }
        for path in paths {
            let url = root.appending(path: path.replacingOccurrences(of: "${CLAUDE_PLUGIN_ROOT}/", with: ""))
            guard let file = reader.json(at: url, problems: &problems) else { continue }
            // Either `{"mcpServers": {...}}` or the map itself.
            maps.append((url, file["mcpServers"] ?? file))
        }
        return maps
    }
}

/// Whether Claude Code loads a project's `.mcp.json` servers: the user approves them one by one,
/// all at once, or rejects them; the answers live in several files and any of them counts.
private struct ProjectApproval {
    var enableAll = false
    var enabled: Set<String> = []
    var disabled: Set<String> = []

    init(_ sources: [JSON]) {
        for source in sources {
            enableAll = enableAll || source["enableAllProjectMcpServers"]?.boolValue == true
            enabled.formUnion(source["enabledMcpjsonServers"]?.stringArray ?? [])
            disabled.formUnion(source["disabledMcpjsonServers"]?.stringArray ?? [])
        }
    }

    func status(of name: String) -> ConfiguredServer.Status {
        if disabled.contains(name) { return .disabled }
        return enableAll || enabled.contains(name) ? .enabled : .awaitingApproval
    }
}
