import SwiftUI

/// View ▸ Show Status Bar, and which items it shows.
struct StatusBarCommands: Commands {
    let registry: StatusBarRegistry

    var body: some Commands {
        CommandGroup(after: .sidebar) {
            Button(registry.isShown ? "Hide Status Bar" : "Show Status Bar") {
                registry.isShown.toggle()
            }
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
