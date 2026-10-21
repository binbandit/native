import Foundation
import Observation

/// The window's undo menu stays available even when its current content has no text responder.
@MainActor
@Observable
public final class UndoHistory {
    private var revision = 0
    public private(set) weak var manager: UndoManager?
    @ObservationIgnored private var observers: [any NSObjectProtocol] = []

    public init() {}

    // Checkpoints can precede a stack mutation. Invalidate observers there, but read the current
    // value when the menu renders rather than caching the stack's previous state.
    public var canUndo: Bool {
        _ = revision
        return manager?.canUndo == true
    }

    public var canRedo: Bool {
        _ = revision
        return manager?.canRedo == true
    }

    public var undoTitle: String {
        _ = revision
        return manager?.undoMenuItemTitle ?? "Undo"
    }

    public var redoTitle: String {
        _ = revision
        return manager?.redoMenuItemTitle ?? "Redo"
    }

    public func track(_ manager: UndoManager?) {
        guard self.manager !== manager else { return }
        observers.forEach(NotificationCenter.default.removeObserver)
        observers.removeAll()
        self.manager = manager
        if let manager {
            for name in [
                Notification.Name.NSUndoManagerCheckpoint, .NSUndoManagerDidCloseUndoGroup,
                .NSUndoManagerDidUndoChange, .NSUndoManagerDidRedoChange,
                .undoableActionDidRemove,
            ] {
                observers.append(
                    NotificationCenter.default.addObserver(forName: name, object: manager, queue: .main) {
                        [weak self] _ in
                        MainActor.assumeIsolated { self?.refresh() }
                    })
            }
        }
        refresh()
    }

    public func undo() {
        manager?.undo()
        refresh()
    }

    public func redo() {
        manager?.redo()
        refresh()
    }

    private func refresh() {
        revision &+= 1
    }

    isolated deinit {
        observers.forEach(NotificationCenter.default.removeObserver)
    }
}
