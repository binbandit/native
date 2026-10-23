import Foundation
import Observation
import Synchronization
import Testing

@testable import Undo

@MainActor
@Suite struct UndoHistoryTests {
    @Test func shortcutHintFollowsTheSpecificOffer() {
        let history = UndoHistory()
        let manager = UndoManager()
        manager.groupsByEvent = false
        history.track(manager)
        manager.beginUndoGrouping()
        let offered = UndoableAction("Archived task", name: "Archive Task", undoManager: manager) { _ in }
        manager.endUndoGrouping()
        #expect(history.willUndo(offered))

        let changed = Mutex(false)
        withObservationTracking {
            _ = history.willUndo(offered)
        } onChange: {
            changed.withLock { $0 = true }
        }
        manager.beginUndoGrouping()
        let draft = NSObject()
        manager.registerUndo(withTarget: draft) { _ in }
        manager.setActionName("Typing")
        manager.endUndoGrouping()
        #expect(changed.withLock { $0 })
        #expect(!history.willUndo(offered))
        history.undo()
        #expect(history.willUndo(offered))
        offered.undo()
        #expect(!history.willUndo(offered))
    }

    @Test func unregisteredAndOtherWindowOffersHaveNoShortcutHint() {
        let history = UndoHistory()
        let manager = UndoManager()
        history.track(manager)
        let unregistered = UndoableAction("Removed host", name: "Remove Host", undoManager: nil) { _ in }
        #expect(!history.willUndo(unregistered))
        let other = UndoManager()
        let elsewhere = UndoableAction("Archived task", name: "Archive Task", undoManager: other) { _ in }
        #expect(!history.willUndo(elsewhere))
    }

    @Test func menuFollowsTheWindowStackWithoutATextResponder() {
        let history = UndoHistory()
        let manager = UndoManager()
        manager.groupsByEvent = false
        history.track(manager)
        #expect(!history.canUndo)

        manager.beginUndoGrouping()
        let action = UndoableAction("Archived task", name: "Archive Task", undoManager: manager) { _ in
        } redo: { _ in
        }
        manager.endUndoGrouping()
        #expect(history.canUndo)
        #expect(history.undoTitle == "Undo Archive Task")

        history.undo()
        #expect(!action.canUndo)
        #expect(!history.canUndo)
        #expect(history.canRedo)
        #expect(history.redoTitle == "Redo Archive Task")

        history.redo()
        #expect(action.canUndo)
        #expect(history.canUndo)
        #expect(!history.canRedo)
    }

    @Test func switchingWindowsStopsObservingTheOldStack() {
        let history = UndoHistory()
        let first = UndoManager()
        let second = UndoManager()
        first.groupsByEvent = false
        history.track(first)
        history.track(second)
        first.beginUndoGrouping()
        _ = UndoableAction("Archived task", name: "Archive Task", undoManager: first) { _ in }
        first.endUndoGrouping()
        #expect(!history.canUndo)
        history.track(nil)
        #expect(history.manager == nil)
        #expect(history.undoTitle == "Undo")
    }

    @Test func expiredDeletionLeavesNoEnabledUndoCommand() {
        let history = UndoHistory()
        let manager = UndoManager()
        manager.groupsByEvent = false
        history.track(manager)
        manager.beginUndoGrouping()
        let action = UndoableAction("Deleted task", name: "Delete Task", undoManager: manager) { _ in }
        manager.endUndoGrouping()
        #expect(history.canUndo)

        let changed = Mutex(false)
        withObservationTracking {
            _ = history.canUndo
        } onChange: {
            changed.withLock { $0 = true }
        }
        action.withdraw()
        #expect(!history.canUndo)
        #expect(changed.withLock { $0 })
    }
}
