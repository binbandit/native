import SwiftUI

/// One project's settings: what it's called and how it looks, how its new tasks start, its scripts,
/// AI instructions, modes and actions, its MCP servers and skills, what archiving does, and removing it
/// from Native. Each value stays with its owner (the project list, the icon store, Git settings,
/// task scripts, AI instructions, project actions, the MCP and skill switches), and those features
/// contribute their own sections; a value left on Default follows the setting for every project.
struct ProjectSettingsPage: View {
    let projectID: Project.ID
    @Environment(\.settingsPlainly) private var plainly

    @Environment(AppModel.self) private var model
    @Environment(SettingsPresentation.self) private var settings

    var body: some View {
        content
            // Removing or archiving it leaves nothing to set here; the main window shows the undo.
            .onChange(of: model.projects.project(projectID) == nil) { _, isGone in
                if isGone { settings.close() }
            }
    }

    @ViewBuilder
    private var content: some View {
        if let project = model.projects.project(projectID) {
            SettingsPage {
                SettingsHeader(
                    project.name,
                    description: Text(
                        "Settings for \(project.name) alone. Anything left on Default follows your settings for every project."
                    ))
                ProjectIdentitySection(project: project)
                if plainly {
                    SettingsRowGroup {
                        SettingsRow(id: ProjectSettingsRows(project: project.id).agent, "New tasks in \(project.name)")
                        {
                            Button("New Tasks…") { settings.open(.newTasks, scopedTo: project.url) }
                        }
                    }
                    ProjectNewTasksSection(project: project, prefixOnly: true)
                } else {
                    ProjectNewTasksSection(project: project)
                }
                ProjectScriptsSection(projectRoot: project.url)
                AIInstructionsProjectSection(projectRoot: project.url)
                ModesProjectSection(project: project)
                ProjectActionsSettingsSection(project: project)
                ProjectToolsSection(project: project)
                ProjectRemovalSection(project: project)
            }
        } else {
            // Archived or removed while its page was open (from the sidebar, or undone elsewhere).
            EmptyStateView(
                "This project isn't open", systemImage: "folder",
                message: "It was archived or removed from Native. Open its folder again to change its settings.",
                actionTitle: "Open Folder…"
            ) {
                settings.close()
                model.isAddingProject = true
            }
            .frame(maxWidth: .infinity, minHeight: SettingsMetrics.pageMaxWidth / 2)
        }
    }
}
