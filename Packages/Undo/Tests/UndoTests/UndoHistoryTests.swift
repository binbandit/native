import Foundation
import Observation
import Synchronization
import Testing

@testable import Undo

@MainActor
@Suite struct UndoHistoryTests {
    @Test func readingAnIdleMenuDoesNotInvalidateIt() async throws {
        let history = UndoHistory()
        let manager = UndoManager()
        history.track(manager)
        let changed = Mutex(false)
        withObservationTracking {
            _ = history.undoTitle
            _ = history.redoTitle
            _ = history.canUndo
            _ = history.canRedo
        } onChange: {
            changed.withLock { $0 = true }
        }

        // Redo queries post checkpoints even with an empty stack. Allow their deferred work
        // to run, as it would between SwiftUI menu updates.
        _ = manager.canRedo
        _ = manager.redoMenuItemTitle
        try await Task.sleep(for: .milliseconds(30))
        #expect(!changed.withLock { $0 })
    }

    @Test func checkpointRefreshIncludesTheRegisteredActionName() async throws {
        let history = UndoHistory()
        let manager = UndoManager()
        manager.groupsByEvent = false
        history.track(manager)
        manager.beginUndoGrouping()
        let action = UndoableAction("Archived task", name: "Archive Task", undoManager: manager) { _ in }

        // Registration checkpoints precede the action and its name, before the group closes.
        try await Task.sleep(for: .milliseconds(30))
        #expect(history.canUndo)
        #expect(history.undoTitle == "Undo Archive Task")
        manager.endUndoGrouping()
        action.withdraw()
        #expect(!history.canUndo)
    }

    @Test func switchingWindowsCancelsAPendingCheckpoint() async throws {
        let history = UndoHistory()
        let first = UndoManager()
        let second = UndoManager()
        first.groupsByEvent = false
        history.track(first)
        first.beginUndoGrouping()
        _ = UndoableAction("Archived task", name: "Archive Task", undoManager: first) { _ in }
        history.track(second)
        first.endUndoGrouping()

        let changed = Mutex(false)
        withObservationTracking {
            _ = history.undoTitle
            _ = history.canUndo
        } onChange: {
            changed.withLock { $0 = true }
        }
        try await Task.sleep(for: .milliseconds(30))
        #expect(history.manager === second)
        #expect(history.undoTitle == "Undo")
        #expect(!history.canUndo)
        #expect(!changed.withLock { $0 })
    }

    @Test func checkpointListenersCanCommitAPendingEdit() {
        let history = UndoHistory()
        let manager = UndoManager()
        manager.groupsByEvent = false
        let committed = Mutex(false)
        let observer = NotificationCenter.default.addObserver(
            forName: .NSUndoManagerCheckpoint, object: manager, queue: .main
        ) { _ in
            let shouldCommit = committed.withLock { committed in
                guard !committed else { return false }
                committed = true
                return true
            }
            guard shouldCommit else { return }
            MainActor.assumeIsolated {
                manager.beginUndoGrouping()
                _ = UndoableAction("Edited draft", name: "Edit", undoManager: manager) { _ in }
                manager.endUndoGrouping()
            }
        }
        defer { NotificationCenter.default.removeObserver(observer) }

        history.track(manager)
        #expect(history.canUndo)
        #expect(history.undoTitle == "Undo Edit")
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
