import ACP
import Foundation
import MCP
import Testing

@testable import NativeOrchestration

@Suite("Coordinator scope")
struct CoordinatorTests {
    @Test("Assignments replace family scope, can be revoked, and never permit delegation or cancellation")
    func assignments() async throws {
        let runtime = FakeRuntime()
        let engine = TaskOrchestrator(runtime: runtime)
        let caller = await runtime.openSession(agent: "codex", id: "coordinator")
        _ = try await engine.startTask(agent: "codex", prompt: "old child", title: nil, for: caller)
        let child = try #require(await runtime.tasks().first)
        let target = await runtime.openSession(agent: "claude", id: "assigned")
        let assigned = OrchestrationTask(
            id: "assigned", session: TaskSessionRef(agent: "claude", id: "assigned"),
            agentName: "Claude", title: "Docs", parent: TaskSessionRef(agent: "codex", id: "coordinator"),
            parentAgentName: "Codex")
        await runtime.setScope(CoordinatorScope(title: "Align docs", tasks: [assigned]), for: caller)
        let list = try await engine.listTasks(for: caller)
        #expect(list.text.contains("assigned by the user"))
        #expect(!list.text.contains(child.id))
        await #expect(throws: MCPToolError.self) { try await engine.getTask(child.id, for: caller) }
        await #expect(throws: MCPToolError.self) {
            try await engine.sendMessage(to: child.id, message: "hidden", for: caller)
        }
        await #expect(throws: MCPToolError.self) {
            try await engine.startTask(agent: "codex", prompt: "new", title: nil, for: caller)
        }
        await #expect(throws: MCPToolError.self) { try await engine.cancelTask(assigned.id, for: caller) }
        let report = try await engine.getTask(assigned.id, for: caller)
        #expect(report.structuredContent?["reply"]?.stringValue == "Recent visible transcript")
        _ = try await engine.sendMessage(to: assigned.id, message: "Align the docs", for: caller)
        let message = try #require(await runtime.delivered.first)
        #expect(TaskPromptFrame(parsing: message.prompt)?.sender == .coordinator(title: "Align docs"))
        #expect(TaskPromptFrame(parsing: message.prompt)?.body == "Align the docs")
        #expect(try await engine.listTasks(for: target).structuredContent?["tasks"] == .array([]))
        await runtime.setScope(CoordinatorScope(title: "Align docs", tasks: []), for: caller)
        await #expect(throws: MCPToolError.self) {
            try await engine.sendMessage(to: assigned.id, message: "revoked", for: caller)
        }
        #expect(await runtime.delivered.count == 1)
    }

    @Test("Summary includes recent visible messages, bounded and without thoughts or tools")
    func summary() throws {
        var state = SessionState()
        for index in 0..<8 {
            let json = """
                {"sessionUpdate":"agent_message_chunk","content":{"type":"text","text":"visible \(index) \(String(repeating: "x", count: 2000))"}}
                """
            state.apply(try JSONDecoder().decode(SessionUpdate.self, from: Data(json.utf8)))
            state.apply(
                try JSONDecoder().decode(
                    SessionUpdate.self,
                    from: Data(
                        #"{"sessionUpdate":"agent_thought_chunk","content":{"type":"text","text":"PRIVATE THOUGHT"}}"#
                            .utf8)))
        }
        let text = CoordinatorScope.summary(of: state)
        #expect(text.count <= 5000)
        #expect(!text.contains("PRIVATE THOUGHT"))
        #expect(text.contains("visible 7"))
        #expect(!text.contains("visible 0"))
    }

    @Test("Read-only is advertised on the permission category, never inferred from Plan")
    func readOnly() throws {
        func options(_ value: String, category: String = "mode") throws -> [ConfigOption] {
            try JSONDecoder().decode(
                [ConfigOption].self,
                from: Data(
                    """
                    [{"id":"mode","name":"Mode","category":"\(category)","type":"select","currentValue":"agent","options":[{"value":"\(value)","name":"\(value)"}]}]
                    """.utf8))
        }
        #expect(CoordinatorScope.readOnlyChoice(in: try options("read-only"))?.value == "read-only")
        #expect(CoordinatorScope.readOnlyChoice(in: try options("plan")) == nil)
        #expect(CoordinatorScope.readOnlyChoice(in: try options("read-only", category: "model")) == nil)
    }

    @Test("Pinned, filtered and archived coordinators never hide matching assigned tasks")
    func ordering() {
        let assignments = ["parent": ["one", "two"]]
        #expect(
            CoordinatorOrdering.grouped([["two"], ["one", "other", "parent"]], assignments: assignments)
                == [[], ["other", "parent", "one", "two"]])
        #expect(
            CoordinatorOrdering.grouped([["parent"], ["one", "other"]], assignments: assignments)
                == [["parent", "one"], ["other"]])
        #expect(
            CoordinatorOrdering.grouped([[], ["one", "other"]], assignments: assignments) == [[], ["one", "other"]])
    }
}
