import NativeCommands
import SwiftUI

extension CommandID {
    static let sessionOpenInDefaultApp: Self = "session.openInDefaultApp"
}

extension NativeCommand {
    /// "Open in <default app>" (⇧⌘O) for the visible task's folder: what the Open In control's left
    /// half does. `location` says where the task's folder is.
    static func openInDefaultApp(
        location: @escaping @MainActor (CommandContext) -> OpenInLocation?, model: OpenInModel = .shared
    ) -> NativeCommand {
        NativeCommand(
            .sessionOpenInDefaultApp, title: "Open in Default App", category: .tasks,
            systemImage: "arrow.up.forward.app", keywords: ["editor", "finder", "folder"]
        ) { context in
            if let location = location(context) {
                model.openInDefaultApp(location)
            }
        }
        .menuTitle { context in
            location(context).flatMap(model.defaultApp(for:)).map { "Open in \($0.name)" } ?? "Open in Default App"
        }
        .available { location($0).flatMap(model.defaultApp(for:)) != nil }
    }
}

/// The menu bar's Open In commands for the visible task's folder, so they're discoverable and every
/// app is reachable from the keyboard; disabled while no task is in view:
///
///     CommandMenu("Session") {
///         OpenInCommands(location: session.map { OpenInLocation(folder: $0.cwd, host: project.host) }, menu: menu)
///     }
///
/// "Open in <default app>" (`session.openInDefaultApp`) comes from the registry; the "Open In"
/// submenu mirrors the control's chevron menu.
struct OpenInCommands: View {
    /// Opens the folder in the default app, for the control's tooltip and its AppKit menu.
    static var shortcut: KeyboardShortcut? {
        CommandRegistry.shared.keyboardShortcut(for: .sessionOpenInDefaultApp)
    }

    let location: OpenInLocation?
    let menu: CommandMenuContext
    private let model: OpenInModel

    init(location: OpenInLocation?, menu: CommandMenuContext, model: OpenInModel = .shared) {
        self.location = location
        self.menu = menu
        self.model = model
    }

    var body: some View {
        CommandMenuItem(.sessionOpenInDefaultApp, in: menu)

        Menu("Open In") {
            if let location {
                OpenInMenuContent(location: location, model: model)
            } else {
                // The menu bar keeps a submenu enabled, so it says why it's empty.
                Button("Open a Task to Choose an App") {}
                    .disabled(true)
            }
        }
    }
}
