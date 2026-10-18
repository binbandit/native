import Foundation

/// Claude Code's installed plugins, for the skills they bring: `plugins/installed_plugins.json`
/// in Claude's config folder lists each plugin's install path, and its skills are in `skills/`.
/// Read only; Claude Code turns plugins on and off itself (`/plugin`).
enum ClaudePlugins {
    static func roots(home: String, environment: [String: String], files: any SkillFileSystem) -> [SkillRoot] {
        let config = environment["CLAUDE_CONFIG_DIR"] ?? SkillPaths.join(home, ".claude")
        guard let data = files.contents(atPath: SkillPaths.join(config, "plugins", "installed_plugins.json")),
            let manifest = try? JSONDecoder().decode(InstalledPlugins.self, from: data)
        else { return [] }
        return manifest.plugins.sorted { $0.key < $1.key }.flatMap { id, installs in
            // "name@marketplace": the name is what Claude Code shows.
            let name = id.split(separator: "@").first.map(String.init) ?? id
            return installs.compactMap(\.installPath).map {
                SkillRoot(path: SkillPaths.join($0, "skills"), scope: .plugin(name), agents: [.claudeCode])
            }
        }
    }

    private struct InstalledPlugins: Decodable {
        struct Install: Decodable {
            var installPath: String?
        }

        var plugins: [String: [Install]]
    }
}

extension SkillAgentFormat {
    /// Every folder these agents read skills from, merged so a folder several agents share is
    /// listed once with all of them.
    public static func roots(
        for formats: Set<SkillAgentFormat>, home: String, environment: [String: String], projects: [URL],
        files: any SkillFileSystem
    ) -> [SkillRoot] {
        var roots = allCases.filter(formats.contains).flatMap {
            $0.roots(home: home, environment: environment, projects: projects)
        }
        if formats.contains(.claudeCode) {
            roots += ClaudePlugins.roots(home: home, environment: environment, files: files)
        }
        return SkillRoot.merged(roots)
    }
}
