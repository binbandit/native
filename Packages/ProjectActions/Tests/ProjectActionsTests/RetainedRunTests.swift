import Foundation
import Testing

@testable import ProjectActions

struct RetainedRunTests {
    private let first = URL(filePath: "/work/project/task-a")
    private let second = URL(filePath: "/work/project/task-b")
    private let test = ProjectAction(id: .init(rawValue: "own:test"), name: "Test", command: "swift test")
    private let lint = ProjectAction(id: .init(rawValue: "own:lint"), name: "Lint", command: "swift format lint")

    @Test func anotherTasksLastActionDoesNotHideRetainedOutput() {
        let runs = [run(test, in: first, at: 20), run(lint, in: second, at: 30)]
        #expect(ProjectActionRetainedRun.latest(in: first, from: runs)?.action.id == test.id)
        #expect(ProjectActionRetainedRun.latest(in: second, from: runs)?.action.id == lint.id)
    }

    @Test func anotherTasksLastActionDoesNotSelectOlderOutput() {
        let runs = [run(lint, in: first, at: 10), run(test, in: first, at: 20), run(lint, in: second, at: 30)]
        #expect(ProjectActionRetainedRun.latest(in: first, from: runs)?.action.id == test.id)
    }

    @Test func terminalAndBackgroundRunsUseTheSameOrdering() {
        var background = lint
        background.presentation = .background
        let runs = [run(test, in: first, at: 20), run(background, in: first, at: 30)]
        #expect(ProjectActionRetainedRun.latest(in: first, from: runs)?.action == background)
    }

    @Test func aTaskWithoutRetainedRunsHasNoSelection() {
        #expect(ProjectActionRetainedRun.latest(in: first, from: [run(lint, in: second, at: 30)]) == nil)
        #expect(ProjectActionRetainedRun.latest(in: first, from: []) == nil)
    }

    private func run(_ action: ProjectAction, in worktree: URL, at seconds: TimeInterval) -> ProjectActionRetainedRun {
        ProjectActionRetainedRun(action: action, worktree: worktree, startedAt: Date(timeIntervalSince1970: seconds))
    }
}
