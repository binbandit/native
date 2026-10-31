import Experiments
import SwiftUI

extension SettingsPane.ID {
    /// A project's own settings page.
    static func project(_ id: Project.ID) -> Self {
        Self("project.\(id.uuidString)")
    }
}

extension SettingsPane {
    /// Settings ▸ Projects ▸ <project>: everything that applies to one project, led by its icon in
    /// the nav. The page reads the project live, so renaming it there renames the page too.
    static func project(_ project: Project, order: Int) -> SettingsPane {
        let rows = ProjectSettingsRows(project: project.id)
        return SettingsPane(
            id: .project(project.id),
            title: project.name,
            systemImage: "folder",
            group: .projects,
            order: order,
            keywords: ["project", "repository", project.folderName],
            searchEntries: {
                var entries = [
                    SettingsSearchEntry(id: rows.name, title: "Name", keywords: ["rename", project.name]),
                    SettingsSearchEntry(id: rows.folder, title: "Folder", keywords: ["finder", "path", "reveal"]),
                    SettingsSearchEntry(
                        id: rows.icon, title: "Icon", keywords: ["favicon", "svg", "emoji", "symbol", "image"]),
                    SettingsSearchEntry(id: rows.agent, title: "Agent for new tasks", keywords: ["default agent"]),
                    SettingsSearchEntry(id: rows.model, title: "Model for new tasks", keywords: ["default model"]),
                    SettingsSearchEntry(
                        id: rows.workspace, title: "New tasks get", keywords: ["worktree", "branch"],
                        plainly: .workspace),
                    SettingsSearchEntry(id: rows.prefix, title: "Branch prefix", keywords: ["github", "username"]),
                    SettingsSearchEntry(
                        id: rows.warmWorktree, title: "Warm worktrees",
                        keywords: ["dependencies", "cache", "setup", "env"]),
                    ProjectActionsSettingsSection.searchEntry(project.id),
                    SettingsSearchEntry(id: rows.mcp, title: "MCP servers", keywords: ["mcp", "tools"]),
                    SettingsSearchEntry(id: rows.skills, title: "Skills", keywords: ["skill"]),
                    SettingsSearchEntry(id: rows.archive, title: "When a task is archived", keywords: ["branch"]),
                    SettingsSearchEntry(
                        id: rows.remove, title: "Delete from Native", keywords: ["remove", "forget"]),
                ]
                if !ExperimentStore.shared.value(of: .warmWorktrees) {
                    entries.removeAll { $0.id == rows.warmWorktree }
                }
                guard SettingsPageMap.isEnabled else { return entries }
                return entries.filter { ![rows.agent, rows.model, rows.workspace].contains($0.id) }
                    + [
                        SettingsSearchEntry(
                            id: rows.agent, title: "New tasks in \(project.name)",
                            keywords: ["agent", "model", "worktree", "defaults"])
                    ]
            },
            content: { ProjectSettingsPage(projectID: project.id) }
        )
        .navIcon { ProjectSettingsNavIcon(project: project) }
    }

    /// A page per open project, in the sidebar's order.
    static func projects(_ projects: [Project]) -> [SettingsPane] {
        projects.enumerated().map { .project($1, order: $0) }
    }
}

/// Where each row of a project's page is, for search to reveal.
struct ProjectSettingsRows {
    let project: Project.ID

    var name: SettingsRowID { row("name") }
    var folder: SettingsRowID { row("folder") }
    var icon: SettingsRowID { row("icon") }
    var agent: SettingsRowID { row("agent") }
    var model: SettingsRowID { row("model") }
    var workspace: SettingsRowID { row("workspace") }
    var prefix: SettingsRowID { row("prefix") }
    var warmWorktree: SettingsRowID { row("warm-worktree") }
    var mcp: SettingsRowID { row("mcp") }
    var skills: SettingsRowID { row("skills") }
    var archive: SettingsRowID { row("archive") }
    var remove: SettingsRowID { row("remove") }

    private func row(_ name: String) -> SettingsRowID {
        SettingsRowID("project.\(project.uuidString).\(name)")
    }
}

/// The project's own icon in the Settings nav, as in the sidebar.
private struct ProjectSettingsNavIcon: View {
    let project: Project
    @Environment(\.projectIconStore) private var injectedIconStore

    var body: some View {
        let store = injectedIconStore ?? .shared
        ProjectAvatar(name: project.name, icon: store.icon(for: project))
            .task(id: project.id) { await store.resolve(project) }
    }
}
