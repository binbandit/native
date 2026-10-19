import NativeCommands

extension CommandID {
    static let projectSettings: Self = "project.settings"
}

extension NativeCommand {
    /// Opens the current project's settings page (File menu, the palette, and the project's menu in
    /// the sidebar). The palette lists each project's page too, as a Settings page.
    static func projectSettings(model: AppModel, settings: SettingsPresentation) -> NativeCommand {
        NativeCommand(
            .projectSettings, title: "Project Settings…", category: .tasks, systemImage: "slider.horizontal.3",
            keywords: ["project", "configure", "rename", "icon", "worktree", "remove"]
        ) { _ in
            guard let project = model.currentProject else { return }
            settings.open(.project(project.id))
        }
        .available { _ in model.currentProject != nil }
        .menuTitle { _ in model.currentProject.map { "\($0.name) Settings…" } ?? "Project Settings…" }
    }
}
