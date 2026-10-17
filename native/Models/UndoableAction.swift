import Foundation

/// Something the user just did that they can take back, for the window's undo toast. The same undo
/// is registered with the window's UndoManager, so ⌘Z works too.
struct UndoableAction: Identifiable {
    let id = UUID()
    /// What just happened: "Archived “Sidebar polish”".
    let message: String
    let undo: () -> Void
}
