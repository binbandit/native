import Foundation

extension UndoManager {
    /// Removes a target's actions and updates any `UndoHistory` following this manager.
    /// Foundation's `removeAllActions(withTarget:)` posts no stack-change notification.
    @MainActor public func removeActions(withTarget target: Any) {
        removeAllActions(withTarget: target)
        NotificationCenter.default.post(name: .undoableActionDidRemove, object: self)
    }
}

extension Notification.Name {
    static let undoableActionDidRemove = Notification.Name("dev.binbandit.native.undoable-action-removed")
}
