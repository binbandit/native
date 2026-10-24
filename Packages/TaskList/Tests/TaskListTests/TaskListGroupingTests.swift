import Testing

@testable import TaskList

struct TaskListGroupingTests {
    struct Task: Equatable {
        let project: String
        let name: String
    }

    @Test func archiveFollowsProjectOrderAndKeepsTaskOrder() {
        let tasks = [
            Task(project: "a", name: "new"), Task(project: "b", name: "first"),
            Task(project: "a", name: "old"), Task(project: "removed", name: "gone"),
        ]
        let groups = TaskListGrouping.archive(
            projects: ["b", "empty", "a"], archivedProjects: ["archived"], tasks: tasks, project: \.project)
        #expect(groups.map(\.project) == ["b", "a", "archived"])
        #expect(groups[1].tasks.map(\.name) == ["new", "old"])
        #expect(groups[2].tasks.isEmpty)
        #expect(groups.map(\.isArchivedProject) == [false, false, true])
    }

    @Test func emptyArchiveHasNoGroups() {
        let groups = TaskListGrouping.archive(
            projects: ["a"], archivedProjects: [], tasks: [Task](), project: \.project)
        #expect(groups.isEmpty)
    }
}
