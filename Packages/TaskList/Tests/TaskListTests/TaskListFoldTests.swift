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
            ordered: ordered, keeping: ["working", "unread"], dates: dates, revealing: ["selected"])
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

    @Test func selectedRecentTaskStillCountsTowardTheRestingLimit() {
        let visible = TaskListFold.visibleIDs(ordered: [1, 2, 3, 4, 5], keeping: [], dates: [:], revealing: [1])
        #expect(visible == [1, 2, 3])
    }

    @Test func selectedOldTaskDoesNotDisplaceRecentRestingTasks() {
        let visible = TaskListFold.visibleIDs(ordered: [1, 2, 3, 4, 5], keeping: [], dates: [:], revealing: [5])
        #expect(visible == [1, 2, 3, 5])
    }
}
