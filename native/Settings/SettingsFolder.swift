import Foundation

/// A folder or file agents read from, as a settings page lists it under "Where agents look":
/// Skills' folders and MCP Servers' configuration files. Built by each page from its own model and
/// shown by `SettingsFoldersSection`.
struct SettingsFolder: Identifiable, Hashable {
    /// The groups a section shows, in this order.
    enum Scope: Int, CaseIterable, Hashable {
        case project, user, plugins, managed, agents
    }

    var id: String { paths.joined(separator: "|") }
    let scope: Scope
    /// The heading it sits under: "This project · app", a project's name, "Your user folder"…
    let section: String
    /// Short: relative to its project, `~` for the home folder, or a plugin's name.
    let label: String
    /// Full paths, the first one shown in Finder. Twins merged into one row keep both.
    let paths: [String]
    /// The agents that read it, in the page's order.
    let readers: [AgentDefinition]
    let exists: Bool
    /// How many things it holds (skills, servers).
    let itemCount: Int
    /// What's wrong in it, when something is: it isn't valid, or a server in it can't be used.
    var problem: String?

    /// Folders beside a twin, a word and its plural in the same parent (an agent that reads both
    /// `skill` and `skills`), become one `skill(s)` row.
    static func mergingTwins(_ folders: [SettingsFolder]) -> [SettingsFolder] {
        var merged: [SettingsFolder] = []
        for folder in folders {
            if let index = merged.firstIndex(where: { $0.isTwin(of: folder) }) {
                merged[index] = merged[index].merged(with: folder)
            } else {
                merged.append(folder)
            }
        }
        return merged
    }

    private func isTwin(of other: SettingsFolder) -> Bool {
        guard section == other.section, let mine = paths.first.map({ URL(filePath: $0) }),
            let theirs = other.paths.first.map({ URL(filePath: $0) }),
            mine.deletingLastPathComponent() == theirs.deletingLastPathComponent()
        else { return false }
        return mine.lastPathComponent + "s" == theirs.lastPathComponent
            || theirs.lastPathComponent + "s" == mine.lastPathComponent
    }

    private func merged(with twin: SettingsFolder) -> SettingsFolder {
        let (singular, plural) = label.count < twin.label.count ? (self, twin) : (twin, self)
        return SettingsFolder(
            scope: scope, section: section, label: singular.label + "(s)", paths: plural.paths + singular.paths,
            readers: readers + twin.readers.filter { reader in !readers.contains { $0.id == reader.id } },
            exists: exists || twin.exists, itemCount: itemCount + twin.itemCount, problem: problem ?? twin.problem)
    }
}
