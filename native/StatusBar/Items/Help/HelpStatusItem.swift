import SwiftUI

/// The "?" at the bar's trailing edge: the keyboard shortcuts sheet, kept out of the composer's
/// row.
struct HelpStatusItem: StatusBarItem {
    let help: KeyboardShortcutsHelp

    let id = "help"
    let title = "Keyboard Shortcuts and Help"
    let placement = StatusBarPlacement.trailing
    /// Past every other trailing item, so it keeps the window's corner and is the last to drop.
    let order = 100

    var content: some View {
        HelpSegment(help: help)
    }
}

private struct HelpSegment: View {
    let help: KeyboardShortcutsHelp

    @Environment(CommandRegistry.self) private var commands

    var body: some View {
        Button(action: help.show) {
            Label {
                Text("Keyboard Shortcuts and Help")
            } icon: {
                StatusBarGlyph("questionmark.circle")
            }
            .labelStyle(.iconOnly)
        }
        .buttonStyle(.statusBarSegment(isActive: help.isShown))
        .help(commands.help("Keyboard Shortcuts and Help", for: .helpKeyboardShortcuts))
        .accessibilityLabel("Keyboard Shortcuts and Help")
    }
}
