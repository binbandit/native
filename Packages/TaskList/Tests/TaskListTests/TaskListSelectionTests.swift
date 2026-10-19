import Testing

@testable import TaskList

@Suite struct TaskListSelectionTests {
    private let order = ["a", "b", "c", "d", "e"]

    @Test func commandClickBringsTheOpenTaskAlong() {
        var selection = TaskListSelection<String>()
        selection.toggle("c", current: "a")
        #expect(selection.ids == ["a", "c"])
        selection.toggle("d", current: "a")
        #expect(selection.ids == ["a", "c", "d"])
        selection.toggle("a", current: "a")
        #expect(selection.ids == ["c", "d"])
    }

    @Test func commandClickOnTheOpenTaskPicksJustIt() {
        var selection = TaskListSelection<String>()
        selection.toggle("a", current: "a")
        #expect(selection.ids == ["a"])
    }

    @Test func shiftClickPicksTheRunFromTheAnchor() {
        var selection = TaskListSelection<String>()
        selection.toggle("b")
        selection.extend(to: "d", in: order)
        #expect(selection.ids == ["b", "c", "d"])
        // The anchor stays, so a second ⇧-click re-picks from it, upwards too.
        selection.extend(to: "a", in: order)
        #expect(selection.ids == ["a", "b"])
    }

    @Test func shiftClickStartsFromTheOpenTaskWithoutAnAnchor() {
        var selection = TaskListSelection<String>()
        selection.extend(to: "c", in: order, current: "e")
        #expect(selection.ids == ["c", "d", "e"])
        #expect(selection.anchor == "e")
    }

    @Test func shiftClickWithNothingToStartFromPicksOne() {
        var selection = TaskListSelection<String>()
        selection.extend(to: "c", in: order)
        #expect(selection.ids == ["c"])
        selection.extend(to: "z", in: order)
        #expect(selection.ids == ["c"])
    }

    @Test func selectAllAndClear() {
        var selection = TaskListSelection<String>()
        selection.selectAll(["b", "c"])
        #expect(selection.ids == ["b", "c"] && selection.anchor == "b")
        selection.clear()
        #expect(selection.isEmpty && selection.anchor == nil)
    }

    @Test func letsGoOfTasksThatAreGone() {
        var selection = TaskListSelection<String>()
        selection.selectAll(order)
        selection.keep(only: ["b", "d"])
        #expect(selection.ids == ["b", "d"])
        #expect(selection.anchor == nil)
        #expect(selection.ordered(by: order) == ["b", "d"])
    }
}
