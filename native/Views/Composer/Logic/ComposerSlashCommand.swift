import ACP

/// A command the slash list offers: one of the agent's, or one Native handles itself (`/goal`).
struct ComposerSlashCommand: Equatable, Identifiable {
    let name: String
    let description: String

    var id: String { name }

    init(name: String, description: String) {
        self.name = name
        self.description = description
    }

    init(_ command: AvailableCommand) {
        self.init(name: command.name, description: command.description)
    }
}
