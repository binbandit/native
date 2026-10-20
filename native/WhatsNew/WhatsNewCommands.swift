import NativeCommands
import SwiftUI

extension CommandID {
    static let appWhatsNew: Self = "app.whatsNew"
}

extension NativeCommand {
    /// Reopens the What's New sheet any time, in the main window.
    static func whatsNew(_ center: WhatsNewCenter) -> NativeCommand {
        NativeCommand(
            .appWhatsNew, title: "What's New", category: .general, systemImage: "gift",
            keywords: ["release notes", "changelog"]
        ) { context in
            context.openMainWindow()
            center.show()
        }
    }
}

/// Help ▸ What's New.
struct WhatsNewCommands: Commands {
    let menu: CommandMenuContext

    var body: some Commands {
        CommandGroup(after: .help) {
            CommandMenuItem(.appWhatsNew, in: menu)
        }
    }
}
