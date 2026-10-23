import Foundation
import Testing

@testable import ACP

struct TaskActivityTests {
    @Test func capturedReadUsesTheReportedFile() throws {
        var state = SessionState()
        state.apply(try Wire.update(Wire.readToolCall))
        state.apply(try Wire.update(Wire.readInputUpdate))
        let activity = TaskActivity(items: state.items, plan: [])
        #expect(activity.verb == "Reading")
        let call = try #require(
            state.items.compactMap { item -> ToolCallState? in
                if case .toolCall(let call) = item { return call }
                return nil
            }.first)
        #expect(activity.object == call.locations.first?.path)
        #expect(activity.progress == nil)
    }

    @Test func finishedToolsAreNotStillRunning() {
        let call = ToolCallState(id: "test", title: "swift test", kind: .execute, status: .completed)
        let activity = TaskActivity(items: [.toolCall(call)], plan: [])
        #expect(activity == TaskActivity(verb: "Working"))
    }

    @Test func countsOnlyReportedPlanSteps() throws {
        let data = Data(
            """
            [{"content":"Inspect","priority":"high","status":"completed"},
             {"content":"Fix","priority":"high","status":"in_progress"},
             {"content":"Verify","priority":"high","status":"pending"}]
            """.utf8)
        let plan = try JSONDecoder().decode([PlanEntry].self, from: data)
        let activity = TaskActivity(items: [TranscriptItem](), plan: plan)
        #expect(activity.progress == .init(completed: 1, total: 3))
    }

    @Test func rejectsImpossibleProgress() {
        #expect(TaskActivity.Progress(completed: 1, total: 0) == nil)
        #expect(TaskActivity.Progress(completed: -1, total: 12) == nil)
        #expect(TaskActivity.Progress(completed: 13, total: 12) == nil)
    }

    @Test func keepsUnknownToolAndDangerousVerbsVerbatim() {
        let call = ToolCallState(id: "overwrite", title: "Overwrite main on github.com")
        #expect(TaskActivity(items: [.toolCall(call)], plan: []).object == "Overwrite main on github.com")
    }
}
