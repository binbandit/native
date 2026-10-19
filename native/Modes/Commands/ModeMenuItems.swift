import Modes
import SwiftUI

/// Session ▸ Mode: Next Mode, every mode the task in view can be in (checked while it's in it),
/// and Edit Modes….
struct ModeMenuItems: View {
    let commands: CommandRegistry

    @FocusedValue(\.activeSession) private var session

    var body: some View {
        let modes = TaskModes.shared
        let catalog = session.map(modes.catalog(for:)) ?? modes.library.catalog(forProjectAt: nil)
        Menu("Mode") {
            CommandMenuItem(.sessionNextMode, in: commands)
            Divider()
            ForEach(catalog.builtIn + catalog.custom) { mode in
                CommandMenuItem(.modeUse(mode.id), in: commands, title: mode.name)
            }
            if !catalog.project.isEmpty {
                Divider()
                ForEach(catalog.project) { mode in
                    CommandMenuItem(.modeUse(mode.id), in: commands, title: mode.name)
                }
            }
            Divider()
            CommandMenuItem(.modesEdit, in: commands)
        }
    }
}
