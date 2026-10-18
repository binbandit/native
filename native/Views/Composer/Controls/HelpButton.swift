import SwiftUI

/// The "?" chip, opening the keyboard shortcuts sheet.
struct HelpButton: View {
    @State private var isPresented = false

    var body: some View {
        Button("Keyboard Shortcuts", systemImage: "questionmark") {
            isPresented = true
        }
        .labelStyle(.iconOnly)
        .buttonStyle(.pill(isSquare: true))
        .help("Keyboard shortcuts")
        .sheet(isPresented: $isPresented) {
            KeyboardShortcutsView()
        }
    }
}
