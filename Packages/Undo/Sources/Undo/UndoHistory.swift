import Foundation
import Observation

/// The window's undo menu stays available even when its current content has no text responder.
@MainActor
@Observable
public final class UndoHistory {
    private struct MenuState: Equatable {
        var canUndo = false
        var canRedo = false
        var undoTitle = "Undo"
        var redoTitle = "Redo"
        var undoActionID: UUID?
        var undoGroupingLevel = 0
    }

    private var menu = MenuState()
    public private(set) weak var manager: UndoManager?
    @ObservationIgnored private var observers: [any NSObjectProtocol] = []
    @ObservationIgnored private var pendingRefresh: Task<Void, Never>?
    @ObservationIgnored private var isRefreshing = false

    public init() {}

    public var canUndo: Bool {
        manager != nil && menu.canUndo
    }

    public var canRedo: Bool {
        manager != nil && menu.canRedo
    }

    public var undoTitle: String {
        manager == nil ? "Undo" : menu.undoTitle
    }

    public var redoTitle: String {
        manager == nil ? "Redo" : menu.redoTitle
    }

    /// Whether the window's next Undo takes back this offer, rather than a newer edit.
    public func willUndo(_ action: UndoableAction) -> Bool {
        _ = menu
        guard let manager else { return false }
        return action.isNextUndo(on: manager)
    }

    public func track(_ manager: UndoManager?) {
        guard self.manager !== manager || (manager == nil && !observers.isEmpty) else { return }
        pendingRefresh?.cancel()
        pendingRefresh = nil
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
                        MainActor.assumeIsolated {
                            if name == .NSUndoManagerCheckpoint {
                                self?.scheduleRefresh()
                            } else {
                                self?.refresh()
                            }
                        }
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
        // UndoManager's redo getters post checkpoints themselves. Reading them while rendering
        // a menu must not invalidate that menu and start another render indefinitely.
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }
        // Checkpoint listeners can commit pending edits. Let the redo queries finish those
        // before sampling Undo, so a newly registered edit appears in the same snapshot.
        let redoTitle = manager?.redoMenuItemTitle ?? "Redo"
        let canRedo = manager?.canRedo == true
        let next = MenuState(
            canUndo: manager?.canUndo == true,
            canRedo: canRedo,
            undoTitle: manager?.undoMenuItemTitle ?? "Undo",
            redoTitle: redoTitle,
            undoActionID: manager?.undoActionUserInfoValue(forKey: UndoableAction.identity) as? UUID,
            undoGroupingLevel: manager?.groupingLevel ?? 0)
        if menu != next { menu = next }
    }

    private func scheduleRefresh() {
        guard !isRefreshing, pendingRefresh == nil else { return }
        // A checkpoint precedes registration and naming. Coalesce the notifications and read
        // after both finish, even when the undo group stays open until the next event.
        pendingRefresh = Task { @MainActor [weak self] in
            guard !Task.isCancelled, let self else { return }
            pendingRefresh = nil
            refresh()
        }
    }

    isolated deinit {
        pendingRefresh?.cancel()
        observers.forEach(NotificationCenter.default.removeObserver)
    }
}
