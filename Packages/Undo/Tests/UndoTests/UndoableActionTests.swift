import Foundation
import Testing

@testable import Undo

/// A window's undo stack, with each change in a group of its own as the run loop makes one per event.
@MainActor
private final class Window {
    let undoManager = UndoManager()

    init() {
        undoManager.groupsByEvent = false
    }

    func event<Result>(_ body: () -> Result) -> Result {
        undoManager.beginUndoGrouping()
        defer { undoManager.endUndoGrouping() }
        return body()
    }

    /// Something else undoable done in the window since, like typing in the composer.
    func type(into draft: Change) {
        event {
            undoManager.registerUndo(withTarget: draft) { $0.undos += 1 }
            undoManager.setActionName("Typing")
        }
    }
}

@MainActor
private final class Change {
    var undos = 0
    var redos = 0

    func action(on undoManager: UndoManager?) -> UndoableAction {
        UndoableAction("Archived “Sidebar polish”.", name: "Archive Task", undoManager: undoManager) { _ in
            self.undos += 1
        } redo: { _ in
            self.redos += 1
        }
    }
}

@MainActor
@Suite struct UndoableActionTests {
    @Test func commandZTakesItBackOnceAndTheToastStopsOffering() {
        let window = Window()
        let change = Change()
        let action = window.event { change.action(on: window.undoManager) }
        #expect(window.undoManager.undoActionName == "Archive Task")

        window.undoManager.undo()
        #expect(change.undos == 1)
        #expect(!action.canUndo)
        action.undo()
        #expect(change.undos == 1)
    }

    @Test func theToastUndoesThroughTheStackSoRedoDoesItAgain() {
        let window = Window()
        let change = Change()
        let action = window.event { change.action(on: window.undoManager) }

        action.undo()
        #expect(change.undos == 1)
        #expect(!window.undoManager.canUndo)
        #expect(window.undoManager.redoActionName == "Archive Task")

        window.undoManager.redo()
        #expect(change.redos == 1)
        #expect(action.canUndo)
        #expect(window.undoManager.undoActionName == "Archive Task")
        window.undoManager.undo()
        #expect(change.undos == 2)
    }

    @Test func theToastTakesItBackFromUnderNewerChangesAndLeavesThemInOrder() {
        let window = Window()
        let change = Change()
        let draft = Change()
        let action = window.event { change.action(on: window.undoManager) }
        window.type(into: draft)

        action.undo()
        #expect(change.undos == 1)
        #expect(window.undoManager.undoActionName == "Typing")
        window.undoManager.undo()
        #expect(draft.undos == 1)
        #expect(!window.undoManager.canUndo)
        #expect(change.undos == 1)
    }

    // The run loop closes an event's group only when it next wakes, so an action registered after an
    // await is still in an open group when the toast's Undo comes.
    @Test func theToastUndoesThroughAGroupTheRunLoopHasNotClosed() {
        let undoManager = UndoManager()
        let change = Change()
        let action = change.action(on: undoManager)
        #expect(undoManager.groupingLevel == 1)

        action.undo()
        #expect(change.undos == 1)
        #expect(undoManager.redoActionName == "Archive Task")
    }

    @Test func withdrawnItLeavesTheStackAndTheToast() {
        let window = Window()
        let change = Change()
        let action = window.event { change.action(on: window.undoManager) }

        action.withdraw()
        #expect(!action.canUndo)
        #expect(!window.undoManager.canUndo)
        action.undo()
        #expect(change.undos == 0)
    }

    @Test func withoutAnUndoManagerOnlyTheToastTakesItBack() {
        let change = Change()
        let action = change.action(on: nil)

        action.undo()
        action.undo()
        #expect(change.undos == 1)
    }

    @Test func aChangeThatCantBeRedoneLeavesNothingToRedo() {
        let window = Window()
        var undos = 0
        _ = window.event {
            UndoableAction("Cleaned up 3 items.", name: "Clean Up Merged", undoManager: window.undoManager) { _ in
                undos += 1
            }
        }

        window.undoManager.undo()
        #expect(undos == 1)
        #expect(!window.undoManager.canRedo)
    }
}
