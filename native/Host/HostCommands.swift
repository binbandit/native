import SwiftUI

/// The menu item that opens the Durable Sessions preview (Phase 1 of `docs/durability.md`).
struct HostCommands: Commands {
    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        CommandGroup(after: .windowArrangement) {
            Button("Durable Sessions (Preview)") {
                openWindow(id: HostPreviewWindow.id)
            }
        }
    }
}
