import NativeCommands
import SwiftUI

extension CommandID {
    static let appearanceSystem: Self = "appearance.system"
    static let appearanceLight: Self = "appearance.light"
    static let appearanceDark: Self = "appearance.dark"
}

extension AppearanceMode {
    var commandID: CommandID {
        switch self {
        case .system: .appearanceSystem
        case .light: .appearanceLight
        case .dark: .appearanceDark
        }
    }
}

extension NativeCommand {
    /// "Appearance: System", "Light" and "Dark", checked while chosen. No default shortcuts
    /// (docs/keyboard.md); the user can give them one.
    static func appearance(_ controller: AppearanceModeController) -> [NativeCommand] {
        AppearanceMode.allCases.map { mode in
            NativeCommand(
                mode.commandID, title: "Appearance: \(mode.title)", category: .view, systemImage: mode.systemImage,
                keywords: ["dark mode", "light mode", "theme", "night", "color scheme"]
            ) { _ in
                controller.mode = mode
            }
            .toggles { _ in controller.mode == mode }
        }
    }
}

/// View ▸ Appearance.
struct AppearanceCommands: Commands {
    let commands: CommandRegistry

    var body: some Commands {
        CommandGroup(after: .sidebar) {
            Menu("Appearance") {
                ForEach(AppearanceMode.allCases) { mode in
                    CommandMenuItem(mode.commandID, in: commands, title: mode.title)
                }
            }
        }
    }
}
