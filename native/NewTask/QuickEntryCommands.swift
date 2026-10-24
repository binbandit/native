import NativeCommands

extension CommandID {
    static let taskCompose: Self = "task.compose"
    static let taskChooseDevice: Self = "task.chooseDevice"
}

extension NativeCommand {
    static func quickEntry(model: AppModel) -> [NativeCommand] {
        [
            NativeCommand(
                .taskCompose, title: "Compose Task", category: .tasks, systemImage: "arrow.up.left.and.arrow.down.right"
            ) { _ in
                model.expandQuickEntry(selection: PlatformTextSelection.capture())
            }
            .available { _ in model.quickEntry.isEnabled },
            NativeCommand(
                .taskChooseDevice, title: "Choose Task Device…", category: .tasks, systemImage: "desktopcomputer"
            ) { _ in
                model.quickEntry.toggle(.device)
            }
            .available { _ in
                model.quickEntry.isEnabled && (model.quickEntry.isPresented || model.composeTask.isPresented)
            },
        ]
    }
}
