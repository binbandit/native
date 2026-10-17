import SwiftUI
import Terminal

/// View ▸ Show Terminal, New Terminal Tab and Close Terminal Tab, for the task in the frontmost
/// window. Every shortcut here is listed in `docs/keyboard.md`, Terminal.
struct TerminalCommands: Commands {
    let store: TerminalStore
    @FocusedValue(\.activeSession) private var session

    var body: some Commands {
        CommandGroup(after: .sidebar) {
            Divider()

            Button(panel?.isVisible == true ? "Hide Terminal" : "Show Terminal") {
                guard let session else { return }
                store.toggle(for: session)
            }
            .keyboardShortcut("`", modifiers: .control)
            .disabled(session == nil)

            Button("New Terminal Tab") {
                guard let session else { return }
                store.newTab(for: session)
            }
            .keyboardShortcut("`", modifiers: [.control, .shift])
            .disabled(session == nil || store.availability != .available)

            Button("Close Terminal Tab") {
                guard let panel, let id = panel.tabs.selectedID else { return }
                panel.requestClose(id)
            }
            .disabled(panel?.isVisible != true || panel?.tabs.selectedID == nil)
        }
    }

    private var panel: TerminalPanelModel? {
        session.map(store.panel(for:))
    }
}
