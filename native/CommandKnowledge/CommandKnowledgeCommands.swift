import NativeCommands

extension CommandID {
    static let commandDiagnostics: Self = "help.commandDiagnostics"
    static let countUnknownPrograms: Self = "privacy.countUnknownPrograms"
    static let clearUnknownPrograms: Self = "privacy.clearUnknownPrograms"
}

extension NativeCommand {
    static func commandKnowledge(settings: SettingsPresentation) -> [NativeCommand] {
        [
            NativeCommand(.commandDiagnostics, title: "Command Diagnostics", category: .general) { _ in
                settings.open(.privacy)
            }.available { _ in CommandKnowledgeCenter.isAvailable }
                .shownInSettings { CommandKnowledgeCenter.isAvailable },
            NativeCommand(.countUnknownPrograms, title: "Count Unknown Programs Locally", category: .general) { _ in
                let center = CommandKnowledgeCenter.shared
                center.setEnabled(!center.userEnabled)
            }.available { _ in CommandKnowledgeCenter.isAvailable && CommandKnowledgeCenter.shared.isAllowed }
                .toggles { _ in CommandKnowledgeCenter.shared.isEnabled }
                .shownInSettings { CommandKnowledgeCenter.isAvailable },
            NativeCommand(.clearUnknownPrograms, title: "Clear Unknown Program Counts", category: .general) { _ in
                Task { await CommandKnowledgeCenter.shared.clear() }
            }.available { _ in CommandKnowledgeCenter.isAvailable }
                .shownInSettings { CommandKnowledgeCenter.isAvailable },
        ]
    }
}
