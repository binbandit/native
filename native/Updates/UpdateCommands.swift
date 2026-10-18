#if os(macOS)
import NativeCommands
import SwiftUI

extension CommandID {
    static let appCheckForUpdates: Self = "app.checkForUpdates"
}

extension NativeCommand {
    /// Opens Settings ▸ Updates in the main window, which shows the check and what it found (or
    /// why this build can't update).
    static func checkForUpdates(_ controller: UpdateController, settings: SettingsPresentation) -> NativeCommand {
        NativeCommand(
            .appCheckForUpdates, title: "Check for Updates…", category: .general,
            systemImage: "arrow.down.circle", keywords: ["version", "upgrade"]
        ) { context in
            context.openMainWindow()
            settings.open(.updates)
            controller.checkForUpdates()
        }
    }
}

/// "Check for Updates…" in the app menu, under About.
struct UpdateCommands: Commands {
    let commands: CommandRegistry

    var body: some Commands {
        CommandGroup(after: .appInfo) {
            CommandMenuItem(.appCheckForUpdates, in: commands)
        }
    }
}
#endif
