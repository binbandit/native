import NativeCommands

extension CommandID {
    static let projectRefresh: Self = "project.refresh"
}

extension NativeCommand {
    static func projectRefresh(model: AppModel) -> NativeCommand {
        NativeCommand(
            .projectRefresh, title: "Refresh Project", category: .tasks, systemImage: "arrow.clockwise",
            keywords: ["git", "pull request", "reload", "tasks"]
        ) { _ in
            guard let project = model.currentProject else { return }
            Task { await model.refreshProject(project.id) }
        }
        .available { _ in
            guard let project = model.currentProject else { return false }
            return !model.refreshingProjects.contains(project.id)
        }
        .menuTitle { _ in model.currentProject.map { "Refresh \($0.name)" } ?? "Refresh Project" }
    }
}
