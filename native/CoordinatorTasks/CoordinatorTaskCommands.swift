import NativeCommands

extension CommandID {
    static let coordinatorNew: Self = "coordinator.new"
    static let coordinatorEdit: Self = "coordinator.edit"
}

extension NativeCommand {
    static func coordinatorTasks(model: AppModel) -> [NativeCommand] {
        [
            NativeCommand(.coordinatorNew, title: "New Coordinator Task…", category: .tasks, systemImage: "person.3") {
                _ in
                model.requestCoordinator()
            }.available { _ in model.offersCoordinatorTasks && model.currentProject != nil },
            NativeCommand(.coordinatorEdit, title: "Edit Assigned Tasks…", category: .tasks, systemImage: "person.3") {
                _ in
                model.requestCoordinator(editing: model.selection)
            }.available { _ in
                model.offersCoordinatorTasks && model.selection.flatMap(model.coordinator) != nil
            },
        ]
    }
}
