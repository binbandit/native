import SwiftUI

/// The menu bar's Open In commands for the visible task's folder, so they're discoverable and every
/// app is reachable from the keyboard:
///
///     CommandMenu("Session") {
///         OpenInCommands(location: session.map { .local($0.cwd) })
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
        Button(model.defaultApp.map { "Open in \($0.name)" } ?? "Open in Default App") {
            if let location {
                model.openInDefaultApp(location)
            }
        }
        .keyboardShortcut(Self.shortcut)
        .disabled(location == nil || model.defaultApp == nil)

        Menu("Open In") {
            ForEach(Array(model.appGroups.enumerated()), id: \.offset) { index, group in
                if index > 0 {
                    Divider()
                }
                ForEach(group) { app in
                    appItem(app)
                }
            }
            Divider()
            Button("Copy Path", systemImage: "doc.on.doc") {
                if let location {
                    model.copyPath(of: location)
                }
            }
        }
        .disabled(location == nil)
    }

    /// Checked when it's the default; choosing it opens the folder there and makes it the default.
    private func appItem(_ app: OpenInApp) -> some View {
        let isDefault = Binding {
            app.id == model.defaultApp?.id
        } set: { _ in
            if let location {
                model.open(location, in: app)
            }
        }
        return Toggle(isOn: isDefault) {
            Label {
                Text(app.name)
            } icon: {
                Image(nsImage: model.icon(for: app))
            }
        }
    }
}
