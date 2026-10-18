import SwiftUI

/// Help ▸ What's New: reopens the sheet any time, in the main window.
struct WhatsNewCommands: Commands {
    let center: WhatsNewCenter

    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        CommandGroup(after: .help) {
            Button("What's New") {
                openWindow(id: "main")
                center.show()
            }
        }
    }
}
