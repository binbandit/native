import NativeCommands
import SwiftUI

extension FocusedValues {
    /// Whether the focused window's changes inspector is showing; published by the session view
    /// so the View menu's ⌘⇧D can toggle it.
    @Entry var gitChangesInspector: Binding<Bool>?
}

extension CommandID {
    static let viewToggleChanges: Self = "view.toggleChanges"
}

extension NativeCommand {
    /// View ▸ Show Changes (⇧⌘D, see `docs/keyboard.md`). Unavailable when the focused window has
    /// nothing to inspect.
    static let gitChanges = NativeCommand(
        .viewToggleChanges, title: "Show or Hide Changes", category: .view, systemImage: "plusminus",
        keywords: ["git", "diff", "inspector", "uncommitted"]
    ) {
        $0.changesInspector?.wrappedValue.toggle()
    }
    .menuTitle { $0.changesInspector?.wrappedValue == true ? "Hide Changes" : "Show Changes" }
    .available { $0.changesInspector != nil }
}
