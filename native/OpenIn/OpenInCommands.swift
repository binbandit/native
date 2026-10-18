import SwiftUI

/// The menu bar's Open In commands for the visible task's folder, so they're discoverable and every
/// app is reachable from the keyboard; disabled while no task is in view:
///
///     CommandMenu("Session") {
///         OpenInCommands(location: session.map { OpenInLocation(folder: $0.cwd, host: project.host) })
///     }
///
/// "Open in <default app>" (⇧⌘O) does what the control's left half does; the "Open In" submenu
/// mirrors its chevron menu.
struct OpenInCommands: View {
    /// Opens the folder in the default app. Listed in `docs/keyboard.md`.
    static let shortcut = KeyboardShortcut("o", modifiers: [.command, .shift])

    let location: OpenInLocation?
    private let model: OpenInModel

    init(location: OpenInLocation?, model: OpenInModel = .shared) {
        self.location = location
        self.model = model
    }

    var body: some View {
        let app = location.flatMap(model.defaultApp(for:))
        Button(app.map { "Open in \($0.name)" } ?? "Open in Default App") {
            if let location {
                model.openInDefaultApp(location)
            }
        }
        .keyboardShortcut(Self.shortcut)
        .disabled(app == nil)

        Menu("Open In") {
            if let location {
                OpenInMenuContent(location: location, model: model)
            }
        }
        .disabled(location == nil)
    }
}
