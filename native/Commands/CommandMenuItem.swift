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
    @FocusedCommandContext private var context

    init(_ id: NativeCommand.ID, in registry: CommandRegistry) {
        self.id = id
        self.registry = registry
    }

    var body: some View {
        if let command = registry.command(id) {
            let title = command.menuTitle?(context) ?? command.title
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
