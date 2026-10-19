#if canImport(Skills)
import Skills
import SwiftUI

/// Where agents look for skills, in the shared folders section: every root the library checks,
/// grouped by scope, with how many skills each holds.
struct SkillFoldersSection: View {
    let library: SkillLibrary
    /// The project the page points at; nil shows every project's folders.
    let project: URL?

    var body: some View {
        SettingsFoldersSection(
            title: "Where agents look for skills",
            folders: SettingsFolder.skills(library: library, project: project),
            place: SettingsFolderNoun("folder"),
            item: SettingsFolderNoun("skill"))
    }
}

extension SettingsFolder {
    /// One row per skills root (a folder and its singular twin, like `.opencode/skill(s)`, share one).
    static func skills(library: SkillLibrary, project: URL?) -> [SettingsFolder] {
        let projects = library.host?.skillProjects ?? []
        let counts = Dictionary(library.items.flatMap(\.places).map { ($0.root.path, 1) }, uniquingKeysWith: +)
        let folders = library.roots.compactMap { root -> SettingsFolder? in
            let scope: Scope
            let section: String
            let label: String
            switch root.scope {
            case .project(let url):
                if let project, SkillPaths.key(project) != SkillPaths.key(url) { return nil }
                scope = .project
                section =
                    project != nil || projects.count == 1
                    ? "This project · \(url.lastPathComponent)" : url.lastPathComponent
                label = String(root.path.dropFirst(SkillPaths.key(url).count + 1))
            case .user, .account:
                scope = .user
                section = "Your user folder"
                label = SkillPaths.abbreviated(root.path, home: library.home)
            case .plugin(let name):
                scope = .plugins
                section = "Plugins"
                label = name
            case .system:
                scope = .agents
                section = "Built into agents"
                label = SkillPaths.abbreviated(root.path, home: library.home)
            }
            return SettingsFolder(
                scope: scope, section: section, label: label, paths: [root.path],
                readers: library.agents.filter { root.agents.contains($0.format) }.map(\.definition),
                exists: library.existingRoots.contains(root.path), itemCount: counts[root.path] ?? 0)
        }
        return mergingTwins(folders)
    }
}
#endif
