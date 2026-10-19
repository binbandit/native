import SwiftUI

/// Whether the keyboard shortcuts sheet is open. One for the app, so Help ▸ Keyboard Shortcuts, its
/// shortcut and the status bar's "?" all open the same sheet over the main window.
@Observable
final class KeyboardShortcutsHelp {
    var isShown = false

    func show() {
        isShown = true
    }
}

extension View {
    /// Shows the keyboard shortcuts sheet whenever `help` asks for it.
    func keyboardShortcutsSheet(_ help: KeyboardShortcutsHelp) -> some View {
        sheet(isPresented: Binding(get: { help.isShown }, set: { help.isShown = $0 })) {
            KeyboardShortcutsView()
        }
    }
}
