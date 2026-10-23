import Foundation
import Testing

@testable import ACP

@Suite struct TaskHandoffTests {
    @Test func includesGoalProgressFilesAndQuestionWithoutPrivateThoughts() {
        var state = SessionState()
        state.appendUserMessage("Fix the export")
        state.apply(.agentThoughtChunk(ContentChunk(content: .text("private reasoning"))))
        state.apply(.agentMessageChunk(ContentChunk(content: .text("Updated the writer. Should I add CSV support?"))))
        state.endTurn(.endTurn)
        let draft = TaskHandoff.draft(
            title: "Export", state: state, objective: "Export matches the spec",
            changedPaths: ["writer.swift", "writer.swift"], openQuestion: "Use commas or tabs?")
        #expect(draft.contains("Export matches the spec"))
        #expect(draft.contains("Updated the writer"))
        #expect(draft.contains("Use commas or tabs?"))
        #expect(draft.components(separatedBy: "- writer.swift").count == 2)
        #expect(!draft.contains("private reasoning"))
    }

    @Test func preservesGoalAndLatestQuestionAcrossLongHistory() {
        var state = SessionState()
        state.appendUserMessage("Original objective")
        for _ in 0..<100 {
            state.apply(.agentMessageChunk(ContentChunk(content: .text(String(repeating: "detail ", count: 300)))))
            state.endTurn(.endTurn)
            state.appendUserMessage("Continue")
        }
        state.apply(.agentMessageChunk(ContentChunk(content: .text("Which format should I use?"))))
        let draft = TaskHandoff.draft(title: "Task", state: state)
        #expect(draft.contains("Original objective"))
        #expect(draft.contains("Which format should I use?"))
        #expect(draft.count < 8_000)
    }

    @Test func includesCompletedEditsEvenWhenGitIsClean() {
        var state = SessionState()
        state.appendUserMessage("Fix the export")
        var edit = ToolCallUpdate(toolCallId: "edit", kind: .edit, status: .completed)
        edit.content = [.diff(FileDiff(path: "Export.swift", oldText: "old", newText: "new"))]
        state.apply(.toolCall(edit))
        var rejected = ToolCallUpdate(toolCallId: "rejected", kind: .edit, status: .failed)
        rejected.content = [.diff(FileDiff(path: "Untouched.swift", oldText: "old", newText: "new"))]
        state.apply(.toolCall(rejected))
        state.endTurn(.endTurn)
        let draft = TaskHandoff.draft(title: "Export", state: state)
        #expect(draft.contains("- Export.swift"))
        #expect(!draft.contains("Untouched.swift"))
    }

    @Test func emptyStateAndUnavailableGitAreExplicit() {
        let draft = TaskHandoff.draft(
            title: "Investigate exports", state: SessionState(), fileStatus: "Git unavailable.")
        #expect(draft.contains("Investigate exports"))
        #expect(draft.contains("No conversation recorded"))
        #expect(draft.contains("No changed files recorded"))
        #expect(draft.contains("Git unavailable"))
        #expect(draft.contains("No explicit open question recorded"))
    }
}
