import NativeCommands

extension CommandID {
    static let sessionChangeAgent: Self = "session.changeAgent"
}

extension NativeCommand {
    static func changeAgent(model: AppModel) -> NativeCommand {
        NativeCommand(
            .sessionChangeAgent, title: "Change Agent…", category: .composer,
            systemImage: "arrow.triangle.swap", keywords: ["harness", "handoff", "continue"]
        ) { context in
            guard let source = context.session else { return }
            model.requestAgentChange(source)
        }
        .available { context in model.offersAgentChange && context.session != nil }
    }
}
