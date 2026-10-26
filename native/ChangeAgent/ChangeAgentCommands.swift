import NativeCommands

extension CommandID {
    static let sessionCancelModelChange: Self = "session.cancelModelChange"
    static let sessionUndoModelChange: Self = "session.undoModelChange"
    static let sessionChangeAgent: Self = "session.changeAgent"
}

extension NativeCommand {
    static func changeAgent(model: AppModel) -> NativeCommand {
        NativeCommand(
            .sessionChangeAgent, title: "Change Agent…", category: .composer,
            systemImage: "arrow.triangle.swap", keywords: ["model", "continue with"]
        ) { context in
            guard let source = context.session else { return }
            model.requestAgentChange(source)
        }
        .available { context in model.offersAgentChange && context.session != nil }
    }
}

extension NativeCommand {
    static func modelChanges(model: AppModel) -> [NativeCommand] {
        [
            NativeCommand(.sessionCancelModelChange, title: "Cancel Pending Model Change", category: .composer) {
                context in
                context.session?.modelChange?.cancel()
            }.available { model.offersAgentModels && $0.session?.modelChange?.isPending == true },
            NativeCommand(.sessionUndoModelChange, title: "Undo Model Change", category: .composer) { context in
                context.session?.modelChange?.undoSelection?.undo()
            }.available { model.offersAgentModels && $0.session?.modelChange?.undoSelection != nil },
        ]
    }
}
