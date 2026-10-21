import Foundation
import Undo

extension AppModel {
    /// The latest action the user can still take back, for the window's undo toast.
    var offeredUndo: UndoableAction? {
        lastUndoable.flatMap { $0.canUndo ? $0 : nil }
    }

    /// Puts something the user just did on the window's undo stack (⌘Z) and offers it on the toast.
    /// `redo` makes the change again for ⇧⌘Z without a new offer; leave it out for a change that
    /// can't be made again.
    @discardableResult
    func offerUndo(
        _ message: String, name: String, undoManager: UndoManager?, undo: @escaping (AppModel) -> Void,
        redo: ((AppModel) -> Void)? = nil
    ) -> UndoableAction {
        let action = undoable(message, name: name, undoManager: undoManager, undo: undo, redo: redo)
        lastUndoable = action
        return action
    }

    /// Puts something the user just did on the window's undo stack only; set `lastUndoable` to offer
    /// it on the toast too.
    func undoable(
        _ message: String, name: String, undoManager: UndoManager?, undo: @escaping (AppModel) -> Void,
        redo: ((AppModel) -> Void)?
    ) -> UndoableAction {
        var redoChange: (@MainActor (UndoableAction) -> Void)?
        if let redo {
            redoChange = { [weak self] _ in
                if let self { redo(self) }
            }
        }
        return UndoableAction(
            message, name: name, undoManager: undoManager,
            undo: { [weak self] _ in
                if let self { undo(self) }
            },
            redo: redoChange)
    }
}
