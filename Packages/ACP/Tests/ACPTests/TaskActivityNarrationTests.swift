import Foundation
import Testing

@testable import ACP

struct TaskActivityNarrationTests {
    @Test func aNewTurnDoesNotReuseEarlierProgress() throws {
        var state = SessionState()
        state.appendUserMessage("Follow this plan")
        let plan = try JSONDecoder().decode(
            [PlanEntry].self,
            from: Data("[{\"content\":\"Verify\",\"priority\":\"high\",\"status\":\"in_progress\"}]".utf8))
        state.apply(.plan(plan))
        #expect(state.taskActivity.progress == .init(completed: 0, total: 1))
        state.endTurn(.endTurn)
        state.appendUserMessage("A different task")
        #expect(state.taskActivity.progress == nil)
        #expect(state.plan == plan)
    }

    @Test func aNewTurnDoesNotNarrateEarlierTools() throws {
        var state = SessionState()
        state.appendUserMessage("Read the file")
        state.apply(try Wire.update(Wire.readToolCall))
        #expect(state.taskActivity.verb == "Reading")
        state.appendUserMessage("A different task")
        #expect(state.taskActivity.verb == "Working")
        #expect(state.taskActivity.object == nil)
    }

    @Test func capturedReadUsesTheReportedFile() throws {
        var state = SessionState()
        state.apply(try Wire.update(Wire.readToolCall))
        state.apply(try Wire.update(Wire.readInputUpdate))
        let activity = TaskActivityNarration(items: state.items, plan: [])
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
        let activity = TaskActivityNarration(items: [.toolCall(call)], plan: [])
        #expect(activity == TaskActivityNarration(verb: "Working"))
    }

    @Test func countsOnlyReportedPlanSteps() throws {
        let data = Data(
            """
            [{"content":"Inspect","priority":"high","status":"completed"},
             {"content":"Fix","priority":"high","status":"in_progress"},
             {"content":"Verify","priority":"high","status":"pending"}]
            """.utf8)
        let plan = try JSONDecoder().decode([PlanEntry].self, from: data)
        let activity = TaskActivityNarration(items: [TranscriptItem](), plan: plan)
        #expect(activity.progress == .init(completed: 1, total: 3))
    }

    @Test func rejectsImpossibleProgress() {
        #expect(TaskActivityNarration.Progress(completed: 1, total: 0) == nil)
        #expect(TaskActivityNarration.Progress(completed: -1, total: 12) == nil)
        #expect(TaskActivityNarration.Progress(completed: 13, total: 12) == nil)
    }

    @Test func keepsUnknownToolAndDangerousVerbsVerbatim() {
        let call = ToolCallState(id: "overwrite", title: "Overwrite main on github.com")
        #expect(TaskActivityNarration(items: [.toolCall(call)], plan: []).object == "Overwrite main on github.com")
    }
}
