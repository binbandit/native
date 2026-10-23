#if DEBUG
import ACP
import SwiftUI
import TaskList

/// Sidebar previews' data: `AppModel.preview()` and what the sidebar's pieces take from it.
enum SidebarPreviewFixtures {
    static func archivedApp() -> AppModel {
        let app = AppModel.preview()
        if let second = app.previewProject(1), let task = app.allSessions(in: second.id).first {
            app.archivedSessions.set(task.id, archived: true)
        }
        return app
    }

    static func defaults(showAgentIcons: Bool = true, showsArchived: Bool = false) -> UserDefaults {
        let defaults = PreviewUserDefaults()
        defaults.set(showAgentIcons, forKey: "sidebar.showAgentIcons")
        defaults.set(showsArchived, forKey: "sidebar.showsArchived")
        return defaults
    }

    /// The populated app, plus a task being set up and a project whose listing failed.
    static func troubledApp() -> AppModel {
        let app = AppModel.preview()
        if let native = app.previewProject(0), let claude = app.runtime(AgentDefinition.ID(rawValue: "claude-code")) {
            app.startingTasks.append(
                StartingTask(
                    project: native.id, agent: claude.agent, isAgentPicked: true,
                    workspaceLabel: "native-preview/composer-drafts"))
        }
        if let pier = app.previewProject(1) {
            app.problems.report(listingProblem(in: pier))
        }
        return app
    }

    static func listingProblem(in project: Project) -> ProjectProblem {
        ProjectProblem(
            project: project.id, work: .listing(AgentDefinition.ID(rawValue: "codex")),
            title: "Couldn’t find Codex’s tasks in pier",
            recovery: "The list shows what Codex reported last time.",
            suggestion: "Check that Codex is signed in, then try again.",
            details: "session/list failed: Internal error: failed to read ~/.codex/sessions (permission denied)")
    }

    /// Every task the app lists in `project`, in the sidebar's order.
    static func sessions(in app: AppModel, project index: Int = 0) -> [SessionSummary] {
        app.previewProject(index).map { app.sessions(in: $0.id) } ?? []
    }

    /// Project icons kept apart from the user's: the preview projects' folders don't exist, so
    /// nothing is found or saved.
    static let iconStore = ProjectIconStore(
        defaults: PreviewUserDefaults(),
        directory: FileManager.default.temporaryDirectory.appending(
            path: "native-preview-icons", directoryHint: .isDirectory))

    static let filtered = TaskFilter(statuses: [.needsYou, .running], agents: ["codex"], requiresPullRequest: true)
}

extension View {
    /// What sidebar pieces read from the environment, as the app's window provides it.
    func sidebarPreviewEnvironment(_ app: AppModel) -> some View {
        environment(app)
            .defaultAppStorage(SidebarPreviewFixtures.defaults())
            .environment(SettingsPresentation())
            .environment(CommandRegistry.shared)
            .environment(\.projectIconStore, SidebarPreviewFixtures.iconStore)
    }
}
#endif
