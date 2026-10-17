import SwiftUI

extension FocusedValues {
    /// Whether the focused window's changes inspector is showing; published by the session view
    /// so the View menu's ⌘⇧D can toggle it.
    @Entry var gitChangesInspector: Binding<Bool>?
}

/// "Show Changes" for the View menu (⇧⌘D, see `docs/keyboard.md`). Disabled when the focused
/// window has nothing to inspect.
struct GitChangesMenuItem: View {
    @FocusedValue(\.gitChangesInspector) private var isPresented

    var body: some View {
        Button(isPresented?.wrappedValue == true ? "Hide Changes" : "Show Changes") {
            isPresented?.wrappedValue.toggle()
        }
        .keyboardShortcut("d", modifiers: [.command, .shift])
        .disabled(isPresented == nil)
    }
}
