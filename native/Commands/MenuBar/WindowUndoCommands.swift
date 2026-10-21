import SwiftUI
import Undo

/// Archive can leave Home on screen, where no text responder handles the standard Edit commands.
struct WindowUndoCommands: Commands {
    let history: UndoHistory

    var body: some Commands {
        CommandGroup(replacing: .undoRedo) {
            Button(history.undoTitle) { PlatformWindow.undo(using: history.manager) }
                .keyboardShortcut("z", modifiers: .command)
                .disabled(!history.canUndo)
            Button(history.redoTitle) { PlatformWindow.redo(using: history.manager) }
                .keyboardShortcut("z", modifiers: [.command, .shift])
                .disabled(!history.canRedo)
        }
    }
}
