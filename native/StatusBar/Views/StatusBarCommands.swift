import NativeCommands
import SwiftUI

extension CommandID {
    static let statusBarToggle: Self = "statusBar.toggle"
}

extension NativeCommand {
    static func statusBar(_ registry: StatusBarRegistry) -> NativeCommand {
        NativeCommand(.statusBarToggle, title: "Show or Hide Status Bar", category: .view, systemImage: "menubar.rectangle") {
            _ in
            registry.isShown.toggle()
        }
        .menuTitle { _ in registry.isShown ? "Hide Status Bar" : "Show Status Bar" }
    }
}

/// View ▸ Show Status Bar, and which items it shows.
struct StatusBarCommands: Commands {
    let registry: StatusBarRegistry
    let commands: CommandRegistry

    var body: some Commands {
        CommandGroup(after: .sidebar) {
            CommandMenuItem(.statusBarToggle, in: commands)
            Menu("Status Bar Items") {
                ForEach(registry.orderedItems) { item in
                    Toggle(item.title, isOn: Binding {
                        registry.isVisible(item.id)
                    } set: {
                        registry.setVisible($0, for: item.id)
                        if $0 { registry.isShown = true }
                    })
                }
            }
        }
    }
}
