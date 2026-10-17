import SwiftUI

/// View ▸ Keep Mac Awake, with ⌃⌘A cycling Off, While Agents Work and On (docs/keyboard.md).
struct KeepAwakeCommands: Commands {
    let controller: KeepAwakeController

    var body: some Commands {
        CommandGroup(after: .sidebar) {
            Menu("Keep Mac Awake") {
                KeepAwakeMenuItems(controller: controller)
                Divider()
                Button("Next Mode") {
                    controller.cycleMode()
                }
                .keyboardShortcut("a", modifiers: [.control, .command])
            }
        }
    }
}
