#if os(macOS)
import SwiftUI

/// "Check for Updates…" in the app menu, under About. It opens Settings ▸ Updates in the main
/// window, which shows the check and what it found (or why this build can't update).
struct UpdateCommands: Commands {
    let controller: UpdateController
    let settings: SettingsPresentation

    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        CommandGroup(after: .appInfo) {
            Button("Check for Updates…") {
                openWindow(id: "main")
                settings.open(.updates)
                controller.checkForUpdates()
            }
        }
    }
}
#endif
