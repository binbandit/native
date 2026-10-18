import SwiftUI

/// The View menu's celebration commands: put the usual look back (or bring a skipped celebration
/// back) with ⌥⇧⌘H, and open the chooser.
struct CelebrationMenuItems: View {
    let center: CelebrationCenter
    let settings: SettingsPresentation
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Group {
            if let skipped = center.resolution.skipped.first, center.resolution.active == nil,
                let event = center.catalog.celebration(skipped.eventID)
            {
                Button("Bring Back \(event.contribution.title.resolved())") { center.resumeToday() }
            } else {
                Button("Restore Usual Appearance") { center.restoreBase() }
                    .disabled(center.resolution.active == nil)
            }
        }
        .keyboardShortcut("h", modifiers: [.command, .option, .shift])

        Button("Celebrations…") {
            openWindow(id: "main")
            settings.open(.celebrations)
        }
    }
}
