import ACP

/// A command the slash list offers: one of the agent's, or one Native handles itself (`/goal`,
/// `/clear`). An agent's command can share a native one's name; both are listed.
struct ComposerSlashCommand: Equatable, Identifiable {
    let name: String
    let description: String
    /// Native runs it rather than sending it to the agent.
    let isNative: Bool

    var id: String { (isNative ? "native/" : "agent/") + name }

    init(native name: String, description: String) {
        self.name = name
        self.description = description
        isNative = true
    }

    init(_ command: AvailableCommand) {
        name = command.name
        description = command.description
        isNative = false
    }
}
