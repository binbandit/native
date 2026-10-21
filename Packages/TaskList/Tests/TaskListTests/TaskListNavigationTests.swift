import Testing

@testable import TaskList

@Suite struct TaskListNavigationTests {
    @Test func archiveOpensNextRemainingTask() {
        #expect(TaskListNavigation.successor(to: 2, removing: [2, 3], in: [1, 2, 3, 4]) == 4)
    }

    @Test func archivingTheEndFallsBackToThePreviousTask() {
        #expect(TaskListNavigation.successor(to: 4, removing: [3, 4], in: [1, 2, 3, 4]) == 2)
    }

    @Test func noSurvivingTaskOrUnknownSelectionHasNoDestination() {
        #expect(TaskListNavigation.successor(to: 1, removing: [1, 2], in: [1, 2]) == nil)
        #expect(TaskListNavigation.successor(to: 3, removing: [3], in: [1, 2]) == nil)
    }
}
