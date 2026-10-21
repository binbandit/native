import Foundation
import Observation
import Synchronization
import Testing

@testable import Undo

@MainActor
@Suite struct UndoHistoryTests {
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
