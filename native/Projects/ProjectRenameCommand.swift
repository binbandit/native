import NativeCommands

extension CommandID {
    static let projectRename: Self = "project.rename"
}

extension NativeCommand {
    static func projectRename(model: AppModel) -> NativeCommand {
        NativeCommand(
            .projectRename, title: "Rename Project…", category: .tasks, systemImage: "pencil",
            keywords: ["display name", "folder", "name"]
        ) { _ in
            guard let project = model.currentProject else { return }
            model.requestRenameProject(project.id)
        }
        .available { _ in model.currentProject?.host == .local }
    }
}
