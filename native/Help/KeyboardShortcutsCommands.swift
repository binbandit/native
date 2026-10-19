import NativeCommands
import SwiftUI

extension CommandID {
    static let helpKeyboardShortcuts: Self = "help.keyboardShortcuts"
}

extension NativeCommand {
    /// Every shortcut on one sheet, in the main window.
    static func keyboardShortcuts(_ help: KeyboardShortcutsHelp) -> NativeCommand {
        NativeCommand(
            .helpKeyboardShortcuts, title: "Keyboard Shortcuts", category: .general, systemImage: "keyboard",
            keywords: ["help", "keys", "hotkeys", "cheat sheet"]
        ) { context in
            context.openMainWindow()
            help.show()
        }
    }
}

/// Help ▸ Keyboard Shortcuts.
struct KeyboardShortcutsCommands: Commands {
    let commands: CommandRegistry

    var body: some Commands {
        CommandGroup(after: .help) {
            CommandMenuItem(.helpKeyboardShortcuts, in: commands)
        }
    }
}
