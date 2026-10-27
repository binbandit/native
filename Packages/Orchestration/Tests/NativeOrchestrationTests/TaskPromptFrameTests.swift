import Testing

@testable import NativeOrchestration

@Suite("Task prompt framing")
struct TaskPromptFrameTests {
    @Test("New task instructions support skills and round-trip through the transcript")
    func skillTask() throws {
        let text = TaskPromptFrame.task("Review the diff", fromParent: "Claude Code")
        #expect(text.contains("native-app skill"))
        let frame = try #require(TaskPromptFrame(parsing: text))
        #expect(frame.kind == .task)
        #expect(frame.sender == .parent(agent: "Claude Code"))
        #expect(frame.body == "Review the diff")
    }

    @Test("Persisted MCP-only task headers still parse")
    func legacyTask() throws {
        let text =
            "[A task from your parent session (Claude Code), handed to you through Native. "
            + "What you say at the end of your turn goes back to it as your reply. "
            + "To message it or its other tasks while you work, use the native MCP tools list_tasks and send_message.]\n\n"
            + "Review the diff"
        let frame = try #require(TaskPromptFrame(parsing: text))
        #expect(frame.kind == .task)
        #expect(frame.sender == .parent(agent: "Claude Code"))
        #expect(frame.body == "Review the diff")
    }
}
