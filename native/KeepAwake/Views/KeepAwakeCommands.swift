import NativeCommands
import SwiftUI

extension CommandID {
    static let keepAwakeNextMode: Self = "keepAwake.nextMode"
}

extension NativeCommand {
    /// ⌃⌘A cycles Off, While Agents Work and On (docs/keyboard.md).
    static func keepAwake(_ controller: KeepAwakeController) -> NativeCommand {
        NativeCommand(
            .keepAwakeNextMode, title: "Keep Mac Awake: Next Mode", category: .view, systemImage: "cup.and.saucer",
            keywords: ["sleep", "caffeinate", "awake"]
        ) { _ in
            controller.cycleMode()
        }
        .menuTitle { _ in "Next Mode" }
    }
}

/// View ▸ Keep Mac Awake.
struct KeepAwakeCommands: Commands {
    let controller: KeepAwakeController
    let commands: CommandRegistry

    var body: some Commands {
        CommandGroup(after: .sidebar) {
            Menu("Keep Mac Awake") {
                KeepAwakeMenuItems(controller: controller)
                Divider()
                CommandMenuItem(.keepAwakeNextMode, in: commands)
            }
        }
    }
}
