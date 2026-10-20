import NativeCommands
import SwiftUI

/// A command as a menu bar item: its title, current shortcut, availability and action all come
/// from the registry, so remapping it in Settings changes the menu at once.
///
///     CommandMenu("Session") {
///         CommandMenuItem(.sessionArchive, in: registry)
///     }
struct CommandMenuItem: View {
    let id: NativeCommand.ID
    let registry: CommandRegistry
    /// A shorter title where the menu says the rest ("Next Mode" in Keep Mac Awake).
    var title: String?
    @FocusedCommandContext private var context

    init(_ id: NativeCommand.ID, in registry: CommandRegistry, title: String? = nil) {
        self.id = id
        self.registry = registry
        self.title = title
    }

    var body: some View {
        if let command = registry.command(id) {
            let title = title ?? command.menuTitle?(context) ?? command.title
            Group {
                if let isOn = command.isOn {
                    Toggle(title, isOn: Binding(get: { isOn(context) }, set: { _ in command.perform(context) }))
                } else {
                    Button(title) { command.perform(context) }
                }
            }
            .keyboardShortcut(registry.keyboardShortcut(for: id))
            .disabled(!command.isAvailable(context))
        }
    }
}
