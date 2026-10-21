import Foundation
import Testing

@testable import TaskList

@Suite struct TaskListFoldTests {
    @Test func keepsAttentionAndSelectionAlongsideThreeRecentTasks() {
        let ordered = ["old", "working", "unread", "selected", "new", "middle", "older"]
        let dates = Dictionary(
            uniqueKeysWithValues: ordered.enumerated().map {
                ($0.element, Date(timeIntervalSince1970: Double($0.offset)))
            })
        let visible = TaskListFold.visibleIDs(
            ordered: ordered, keeping: ["working", "unread", "selected"], dates: dates)
        #expect(ordered.filter(visible.contains) == ["working", "unread", "selected", "new", "middle", "older"])
    }

    @Test func preservesUserOrderForTiedOrMissingDates() {
        let visible = TaskListFold.visibleIDs(ordered: [4, 1, 3, 2, 5], keeping: [], dates: [:])
        #expect(visible == [4, 1, 3])
    }

    @Test func emptyAndShortListsDoNotFold() {
        #expect(TaskListFold.visibleIDs(ordered: [Int](), keeping: [], dates: [:]).isEmpty)
        #expect(TaskListFold.visibleIDs(ordered: [1, 2], keeping: [], dates: [:]) == [1, 2])
    }

    @Test func selectedOldTaskDoesNotDisplaceRecentRestingTasks() {
        let visible = TaskListFold.visibleIDs(ordered: [1, 2, 3, 4, 5], keeping: [5], dates: [:])
        #expect(visible == [1, 2, 3, 5])
    }
}
