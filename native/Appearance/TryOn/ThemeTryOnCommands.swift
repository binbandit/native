import NativeCommands
import SwiftUI

extension CommandID {
    static let appearanceTryOn: Self = "appearance.tryOn"
}

extension NativeCommand {
    /// View ▸ Appearance ▸ Try On Themes…: on the task in view, else the latest one with changes.
    /// No default shortcut (docs/keyboard.md); unavailable while an organization sets the code theme.
    static func themeTryOn(_ tryOn: ThemeTryOnModel) -> NativeCommand {
        NativeCommand(
            .appearanceTryOn, title: "Try On Themes…", category: .view, systemImage: "eye",
            keywords: ["code theme", "colors", "syntax", "preview", "dark mode", "light mode"]
        ) { context in
            tryOn.start(on: context.session?.key)
        }
        .available { _ in tryOn.isAvailable }
    }
}
