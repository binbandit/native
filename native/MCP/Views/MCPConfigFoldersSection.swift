import MCPClient
import SwiftUI

/// Where agents look for MCP servers, in the shared folders section the Skills page uses too: every
/// file an agent's own configuration is read from, grouped by scope, with how many servers it holds
/// and which agents read it. A file that can't be read says why on its row; problems in files the
/// list doesn't show, and connectors that come with an account rather than a file, follow it.
struct MCPConfigFoldersSection: View {
    @Environment(\.projectDisplayName) private var projectDisplayName
    let library: MCPLibrary
    /// The project the page points at; nil shows every project's files.
    let project: URL?

    var body: some View {
        let folders = SettingsFolder.mcpConfigurations(
            library: library, project: project, projectDisplayName: projectDisplayName.callAsFunction)
        SettingsFoldersSection(
            title: "Where agents look for MCP servers",
            folders: folders,
            place: SettingsFolderNoun("file"),
            item: SettingsFolderNoun("server")
        ) {
            notes(listed: Set(folders.flatMap(\.paths).map { ProjectPath.key(URL(filePath: $0)) }))
        }
    }

    @ViewBuilder
    private func notes(listed: Set<String>) -> some View {
        let configurations = Self.formats(of: library.agents).compactMap(library.configuration(of:))
        let problems = configurations.flatMap(\.problems).filter { !listed.contains(ProjectPath.key($0.file)) }
        let connectors = configurations.flatMap(\.accountConnectors)
        if !problems.isEmpty || !connectors.isEmpty {
            VStack(alignment: .leading, spacing: DS.Space.xs) {
                // Keyed by place: a file can have more than one problem.
                ForEach(Array(problems.enumerated()), id: \.offset) { _, problem in
                    Text("\(problem.file.abbreviatedPath): \(problem.message)")
                        .settingsText(.caption)
                        .foregroundStyle(.dsDanger)
                        .textSelection(.enabled)
                }
                if !connectors.isEmpty {
                    Text(
                        "Also connectors from your claude.ai account: \(connectors.map { $0.replacingOccurrences(of: "claude.ai ", with: "") }.joined(separator: ", ")). Claude Code loads them when you sign in with that account."
                    )
                    .settingsText(.caption)
                    .foregroundStyle(.dsTextTertiary)
                    .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    /// Each configuration format once, in the agents' order: agents sharing one read the same files.
    fileprivate static func formats(of agents: [MCPAgent]) -> [AgentConfigFormat] {
        agents.reduce(into: []) { formats, agent in
            if !formats.contains(agent.format) { formats.append(agent.format) }
        }
    }
}

extension SettingsFolder {
    /// One row per configuration file, read by every agent with that file's format.
    static func mcpConfigurations(
        library: MCPLibrary, project: URL?, projectDisplayName: @MainActor (URL) -> String = { $0.lastPathComponent }
    ) -> [SettingsFolder] {
        let projects = library.host?.mcpProjects ?? []
        return MCPConfigFoldersSection.formats(of: library.agents).flatMap { format -> [SettingsFolder] in
            guard let configuration = library.configuration(of: format) else { return [] }
            let readers = library.agents.filter { $0.format == format }.map(\.definition)
            return configuration.files.compactMap { file in
                mcpFile(
                    file, in: configuration, readers: readers, project: project, projectCount: projects.count,
                    projectDisplayName: projectDisplayName)
            }
        }
    }

    private static func mcpFile(
        _ file: ConfigFile, in configuration: AgentMCPConfiguration, readers: [AgentDefinition], project: URL?,
        projectCount: Int, projectDisplayName: @MainActor (URL) -> String
    ) -> SettingsFolder? {
        let path = file.url.path(percentEncoded: false)
        let scope: Scope
        let section: String
        let label: String
        switch file.scope {
        case .project(let url), .local(let url):
            let root = ProjectPath.key(url)
            if let project, ProjectPath.key(project) != root { return nil }
            scope = .project
            section =
                project != nil || projectCount == 1
                ? "This project · \(projectDisplayName(url))" : projectDisplayName(url)
            label = path.hasPrefix(root + "/") ? String(path.dropFirst(root.count + 1)) : file.url.abbreviatedPath
        case .user:
            scope = .user
            section = "Your user folder"
            label = file.url.abbreviatedPath
        case .plugin(let name):
            scope = .plugins
            section = "Plugins"
            label = name
        case .managed:
            scope = .managed
            section = "Set by your organization"
            label = file.url.abbreviatedPath
        }
        let key = ProjectPath.key(file.url)
        let problems = configuration.problems.filter { ProjectPath.key($0.file) == key }.map(\.message)
        return SettingsFolder(
            scope: scope, section: section, label: label, paths: [path], readers: readers, exists: file.exists,
            itemCount: configuration.servers.count { ProjectPath.key($0.source) == key },
            problem: problems.isEmpty ? nil : problems.joined(separator: " "))
    }
}
