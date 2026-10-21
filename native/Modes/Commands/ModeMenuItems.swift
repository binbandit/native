import Modes
import SwiftUI

/// Session ▸ Mode: Next Mode, every mode the task in view can be in (checked while it's in it),
/// and Edit Modes….
struct ModeMenuItems: View {
    let menu: CommandMenuContext

    var body: some View {
        let modes = TaskModes.shared
        let catalog = menu.context.session.map(modes.catalog(for:)) ?? modes.library.catalog(forProjectAt: nil)
        Menu("Mode") {
            CommandMenuItem(.sessionNextMode, in: menu)
            Divider()
            ForEach(catalog.builtIn + catalog.custom) { mode in
                CommandMenuItem(.modeUse(mode.id), in: menu, title: mode.name)
            }
            if !catalog.project.isEmpty {
                Divider()
                ForEach(catalog.project) { mode in
                    CommandMenuItem(.modeUse(mode.id), in: menu, title: mode.name)
                }
            }
            Divider()
            CommandMenuItem(.modesEdit, in: menu)
        }
    }
}

#if NATIVE_PREVIEWS_WIP
#Preview("Task ▸ Mode") {
    DSPreviewPair {
        Menu("Task") {
            ModeMenuItems(menu: CommandMenuContext(registry: .shared, context: CommandContext()))
        }
        .fixedSize()
    }
}
#endif
