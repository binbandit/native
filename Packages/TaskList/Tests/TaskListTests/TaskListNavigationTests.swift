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

    @Test func successorSkipsTasksHiddenByTheWindowFilter() {
        let tasks = [
            TaskFacts(agent: "selected", title: "A"),
            TaskFacts(agent: "other", title: "Hidden"),
            TaskFacts(agent: "selected", title: "B"),
            TaskFacts(agent: "selected", title: "C"),
        ]
        let order = TaskFilter(agents: ["selected"]).apply(to: tasks) { $0 }.map(\.title)
        #expect(TaskListNavigation.successor(to: "A", removing: ["A"], in: order) == "B")
        #expect(TaskListNavigation.successor(to: "A", removing: ["A", "B"], in: order) == "C")
    }

    @Test func successorFollowsNameSortInsteadOfRecentOrder() {
        let tasks = ["A", "C", "B"].map { TaskFacts(agent: "selected", title: $0) }
        let order = TaskFilter(sort: .name).apply(to: tasks) { $0 }.map(\.title)
        #expect(TaskListNavigation.successor(to: "A", removing: ["A"], in: order) == "B")
        #expect(TaskListNavigation.successor(to: "C", removing: ["C"], in: order) == "B")
    }
}
