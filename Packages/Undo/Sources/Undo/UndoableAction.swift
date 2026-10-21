import Foundation
import Observation

/// Something the user just did that they can take back from two places: the window's undo stack
/// (⌘Z) and an undo toast. The two agree: taken back from either, it's undone once and the toast
/// stops offering it, and Redo (⇧⌘Z) does it again.
///
/// It goes on the stack when it's made, so the stack keeps the order things were done in even when
/// the toast waits for slower work to say what happened.
@MainActor
@Observable
public final class UndoableAction: Identifiable {
    public let id = UUID()
    /// What happened, for the toast: "Archived “Sidebar polish”."
    public var message: String
    /// Whether it can be taken back: done or redone, and neither undone nor withdrawn since. The toast
    /// offers it only while this holds.
    public private(set) var canUndo = true

    private let name: String
    @ObservationIgnored private weak var undoManager: UndoManager?
    private let undoChange: @MainActor (UndoableAction) -> Void
    private let redoChange: (@MainActor (UndoableAction) -> Void)?

    /// Puts the action on top of `undoManager`'s stack as `name`, which Edit ▸ Undo shows ("Archive
    /// Task"). `undo` takes the change back; `redo`, for a change that can be made again, makes it
    /// without offering a new undo, since this one goes back on the stack. Both get the action, for work
    /// that has to withdraw it later. Without an undo manager only the toast can take it back.
    public init(
        _ message: String, name: String, undoManager: UndoManager?,
        undo: @escaping @MainActor (UndoableAction) -> Void,
        redo: (@MainActor (UndoableAction) -> Void)? = nil
    ) {
        self.message = message
        self.name = name
        self.undoManager = undoManager
        undoChange = undo
        redoChange = redo
        register { $0.undoFromStack() }
    }

    /// Takes it back from the toast. While it's the latest thing on the stack, that's the stack's own
    /// Undo, so Redo can do it again; under something done since, it's taken back on its own and leaves
    /// the stack, and the newer things stay where they are.
    public func undo() {
        guard canUndo else { return }
        if let undoManager, isNextUndo(on: undoManager) {
            undoManager.undo()
        } else {
            undoManager?.removeAllActions(withTarget: self)
            takeBack()
        }
    }

    /// Takes it off the stack and the toast for good, once the change can't be taken back (a deletion
    /// carried out after its grace period).
    public func withdraw() {
        canUndo = false
        undoManager?.removeAllActions(withTarget: self)
    }

    private static let identity = UndoManager.UserInfoKey("dev.binbandit.native.undoable-action")

    private func isNextUndo(on undoManager: UndoManager) -> Bool {
        // `undo()` closes the group the run loop opened for the current event, but no deeper one.
        let isClosable =
            undoManager.groupingLevel == 0 || (undoManager.groupsByEvent && undoManager.groupingLevel == 1)
        return isClosable && undoManager.undoActionUserInfoValue(forKey: Self.identity) as? UUID == id
    }

    private func register(_ handler: @escaping @MainActor (UndoableAction) -> Void) {
        guard let undoManager else { return }
        // The stack holds its targets weakly, so the handler keeps the action alive while it's there.
        undoManager.registerUndo(withTarget: self) { [self] _ in handler(self) }
        undoManager.setActionName(name)
        undoManager.setActionUserInfoValue(id, forKey: Self.identity)
    }

    private func undoFromStack() {
        takeBack()
        // Registered while undoing, it goes on the redo stack.
        if redoChange != nil {
            register { $0.redoFromStack() }
        }
    }

    private func redoFromStack() {
        redoChange?(self)
        canUndo = true
        register { $0.undoFromStack() }
    }

    private func takeBack() {
        canUndo = false
        undoChange(self)
    }
}
