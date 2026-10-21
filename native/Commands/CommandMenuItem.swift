import NativeCommands
import SwiftUI

/// A command as a menu bar item: its title, current shortcut, availability and action all come
/// from the registry, so remapping it in Settings changes the menu at once.
///
///     CommandMenu("Session") {
///         CommandMenuItem(.sessionArchive, in: menu)
///     }
///
/// The context comes from the menu bar, which reads the frontmost window's once for all of its
/// items (`NativeMenuBar`) rather than each item reading eight focused values of its own.
struct CommandMenuItem: View {
    let id: NativeCommand.ID
    let menu: CommandMenuContext
    /// A shorter title where the menu says the rest ("Next Mode" in Keep Mac Awake).
    var title: String?

    init(_ id: NativeCommand.ID, in menu: CommandMenuContext, title: String? = nil) {
        self.id = id
        self.menu = menu
        self.title = title
    }

    var body: some View {
        if let command = menu.registry.command(id) {
            let context = menu.context
            let title = title ?? command.menuTitle?(context) ?? command.title
            Group {
                if let isOn = command.isOn {
                    Toggle(title, isOn: Binding(get: { isOn(context) }, set: { _ in command.perform(context) }))
                } else {
                    Button(title) { command.perform(context) }
                }
            }
            .keyboardShortcut(menu.registry.keyboardShortcut(for: id))
            .disabled(!command.isAvailable(context))
        }
    }
}
