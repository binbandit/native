#if canImport(Skills)
import Skills
import SwiftUI

/// Where agents look for skills: reference, so it starts collapsed behind one summary row. Opened,
/// folders are grouped by scope, one row each with a short path, the agents that read it and how
/// many skills it holds. Folders that don't exist wait behind their own disclosure.
struct SkillFoldersSection: View {
    let library: SkillLibrary
    /// The project the page points at; nil shows every project's folders.
    let project: URL?

    @State private var isExpanded = false
    @State private var showsMissing = false

    private var folders: [SkillFolderRowModel] {
        SkillFolderRowModel.rows(library: library, project: project)
    }

    var body: some View {
        let folders = folders
        let existing = folders.filter(\.exists)
        let missing = folders.count - existing.count
        VStack(alignment: .leading, spacing: DS.Space.lg) {
            SettingsRow(
                "Where agents look for skills",
                description: Text(
                    summary(withSkills: existing.filter { $0.skillCount > 0 }.count, checked: folders.count))
            ) {
                MCPExpandButton(isExpanded: $isExpanded, name: "skills folders")
            }
            if isExpanded {
                VStack(alignment: .leading, spacing: DS.Space.xl) {
                    ForEach(SkillFolderRowModel.Group.allCases, id: \.self) { group in
                        groupView(group, rows: folders.filter { $0.group == group && ($0.exists || showsMissing) })
                    }
                    if missing > 0 {
                        Button(
                            showsMissing
                                ? "Hide folders that don't exist" : "Show folders that don't exist yet (\(missing))"
                        ) {
                            withAnimation(.dsDisclosure) { showsMissing.toggle() }
                        }
                        .buttonStyle(.ds(.ghost, size: .small))
                    }
                }
                .transition(.opacity)
            }
        }
    }

    private func summary(withSkills: Int, checked: Int) -> String {
        let others = checked - withSkills
        let first = withSkills == 1 ? "1 folder with skills" : "\(withSkills) folders with skills"
        return others > 0 ? "\(first) · \(others) more checked" : first
    }

    @ViewBuilder
    private func groupView(_ group: SkillFolderRowModel.Group, rows: [SkillFolderRowModel]) -> some View {
        let byProject = Dictionary(grouping: rows, by: \.sectionTitle)
        ForEach(byProject.keys.sorted(), id: \.self) { title in
            VStack(alignment: .leading, spacing: DS.Space.md) {
                Text(title)
                    .settingsText(.caption)
                    .foregroundStyle(.dsTextSecondary)
                // A dense list: reference rows, not settings, so they sit closer than settings rows.
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array((byProject[title] ?? []).enumerated()), id: \.element.id) { index, row in
                        if index > 0 { SeparatorLine() }
                        SkillFolderRow(row: row, agents: library.agents)
                    }
                }
                }
            }
        }
    }
}

/// One skills folder (or a folder and its singular twin, like `.opencode/skill(s)`).
struct SkillFolderRowModel: Identifiable, Hashable {
    enum Group: Int, CaseIterable, Hashable {
        case project, user, plugins, agents
    }

    var id: String { paths.joined(separator: "|") }
    let group: Group
    /// "This project", a project's name, "Your user folder", "Plugins", "Built into agents".
    let sectionTitle: String
    /// Relative to the project, `~` for the home folder, or a plugin's name.
    let label: String
    let paths: [String]
    let agents: Set<SkillAgentFormat>
    let exists: Bool
    let skillCount: Int

    static func rows(library: SkillLibrary, project: URL?) -> [SkillFolderRowModel] {
        let projects = library.host?.skillProjects ?? []
        let counts = Dictionary(
            library.items.flatMap(\.places).map { ($0.root.path, 1) }, uniquingKeysWith: +)
        let rows = library.roots.compactMap { root -> SkillFolderRowModel? in
            let group: Group
            let title: String
            let label: String
            switch root.scope {
            case .project(let url):
                if let project, SkillPaths.key(project) != SkillPaths.key(url) { return nil }
                group = .project
                title =
                    project != nil || projects.count == 1
                    ? "This project · \(url.lastPathComponent)" : url.lastPathComponent
                label = String(root.path.dropFirst(SkillPaths.key(url).count + 1))
            case .user, .account:
                group = .user
                title = "Your user folder"
                label = SkillPaths.abbreviated(root.path, home: library.home)
            case .plugin(let name):
                group = .plugins
                title = "Plugins"
                label = name
            case .system:
                group = .agents
                title = "Built into agents"
                label = SkillPaths.abbreviated(root.path, home: library.home)
            }
            return SkillFolderRowModel(
                group: group, sectionTitle: title, label: label, paths: [root.path], agents: root.agents,
                exists: library.existingRoots.contains(root.path), skillCount: counts[root.path] ?? 0)
        }
        return mergingSingulars(rows)
    }

    /// `skill` and `skills` side by side (OpenCode reads both) become one `skill(s)` row.
    private static func mergingSingulars(_ rows: [SkillFolderRowModel]) -> [SkillFolderRowModel] {
        var merged: [SkillFolderRowModel] = []
        for row in rows {
            if row.label.hasSuffix("/skill"),
                let index = merged.firstIndex(where: {
                    $0.sectionTitle == row.sectionTitle && $0.label == row.label + "s"
                })
            {
                let plural = merged[index]
                merged[index] = SkillFolderRowModel(
                    group: plural.group, sectionTitle: plural.sectionTitle, label: row.label + "(s)",
                    paths: plural.paths + row.paths, agents: plural.agents.union(row.agents),
                    exists: plural.exists || row.exists, skillCount: plural.skillCount + row.skillCount)
            } else if row.label.hasSuffix("/skills"),
                let index = merged.firstIndex(where: {
                    $0.sectionTitle == row.sectionTitle && $0.label == String(row.label.dropLast())
                })
            {
                let singular = merged[index]
                merged[index] = SkillFolderRowModel(
                    group: row.group, sectionTitle: row.sectionTitle, label: singular.label + "(s)",
                    paths: row.paths + singular.paths, agents: row.agents.union(singular.agents),
                    exists: row.exists || singular.exists, skillCount: row.skillCount + singular.skillCount)
            } else {
                merged.append(row)
            }
        }
        return merged
    }
}

/// A folder row: short path, the agents reading it as icons, its skill count, and Show in Finder
/// on hover, in the context menu, or always where there's no hover.
struct SkillFolderRow: View {
    let row: SkillFolderRowModel
    let agents: [SkillsAgent]

    @State private var isHovered = false

    private var readers: [SkillsAgent] {
        agents.filter { row.agents.contains($0.format) }
    }

    private var count: String {
        guard row.exists else { return "not created" }
        return switch row.skillCount {
        case 0: "empty"
        case 1: "1 skill"
        default: "\(row.skillCount) skills"
        }
    }

    private var revealPath: String? {
        guard PlatformFileBrowser.canReveal, row.exists else { return nil }
        return row.paths.first
    }

    var body: some View {
        HStack(spacing: DS.Space.lg) {
            HStack(alignment: .firstTextBaseline, spacing: DS.Space.md) {
                Text(row.label)
                    .settingsText(.mono)
                    .foregroundStyle(row.exists ? .dsTextSecondary : .dsTextTertiary)
                    .textSelection(.enabled)
                    .help(row.paths.joined(separator: "\n"))
                Text(count)
                    .settingsText(.caption)
                    .foregroundStyle(.dsTextTertiary)
            }
            Spacer(minLength: DS.Space.md)
            if let revealPath, isHovered || DS.isTouchPlatform {
                Button("Show") { PlatformFileBrowser.reveal(URL(filePath: revealPath)) }
                    .buttonStyle(.ds(.ghost, size: .small))
                    .accessibilityLabel("Show \(row.label) in Finder")
            }
            HStack(spacing: DS.Space.xs) {
                ForEach(readers) { agent in
                    AgentIcon(agent: agent.definition)
                        .help(agent.name)
                        .accessibilityLabel(agent.name)
                }
            }
        }
        .frame(minHeight: DS.Size.rowMinHeight)
        .contentShape(.rect)
        .onHover { isHovered = $0 }
        .contextMenu {
            if let revealPath {
                Button("Show in Finder") { PlatformFileBrowser.reveal(URL(filePath: revealPath)) }
            }
        }
    }
}
#endif
