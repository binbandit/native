import ACP
import Foundation
import MCP
import Testing

@testable import NativeOrchestration

@Suite("The orchestration engine")
struct OrchestratorTests {
    private func tool(_ name: String, _ orchestrator: TaskOrchestrator) throws -> MCPTool<OrchestrationCaller> {
        try #require(OrchestrationTools.all(orchestrator).first { $0.name == name })
    }

    @Test("start_task frames the prompt for the task's agent and remembers the task")
    func startsTasks() async throws {
        let runtime = FakeRuntime()
        let orchestrator = TaskOrchestrator(runtime: runtime)
        let parent = await runtime.openSession(agent: "claude", id: "p1")

        let result = try await orchestrator.startTask(
            agent: "codex", prompt: "  Review the diff  ", title: nil, for: parent)

        let request = try #require(await runtime.started.first)
        #expect(request.agent.id == "codex")
        #expect(request.parent == TaskSessionRef(agent: "claude", id: "p1"))
        #expect(request.title == "Review the diff")
        #expect(request.text == "Review the diff")
        #expect(TaskPromptFrame(parsing: request.prompt)?.sender == .parent(agent: "Claude Code"))
        #expect(result.text.hasPrefix("Started \(request.id) (Codex: Review the diff)."))
        #expect(result.structuredContent?["status"]?.stringValue == "running")
        #expect(await runtime.tasks().map(\.id) == [request.id])
    }

    @Test("A task reaches its parent and siblings, and can't cancel them")
    func peers() async throws {
        let runtime = FakeRuntime()
        let orchestrator = TaskOrchestrator(runtime: runtime)
        let parent = await runtime.openSession(agent: "claude", id: "p1")
        _ = try await orchestrator.startTask(agent: "codex", prompt: "one", title: "One", for: parent)
        _ = try await orchestrator.startTask(agent: "claude", prompt: "two", title: "Two", for: parent)
        let tasks = await runtime.tasks()
        let first = try #require(await runtime.caller(ofTask: tasks[0]))

        let listing = try await orchestrator.listTasks(for: first)
        guard case .array(let entries)? = listing.structuredContent?["tasks"] else {
            Issue.record("No tasks listed")
            return
        }
        let relations = entries.compactMap { $0["relation"]?.stringValue }
        #expect(relations == ["parent", "sibling"])
        #expect(listing.structuredContent?["you"]?.stringValue == tasks[0].id)

        await #expect(throws: MCPToolError.self) {
            try await orchestrator.cancelTask(tasks[1].id, for: first)
        }
        _ = try await orchestrator.sendMessage(to: "parent", message: "Done with one", for: first)
        let message = try #require(await runtime.delivered.first)
        #expect(message.recipient == TaskSessionRef(agent: "claude", id: "p1"))
        #expect(TaskPromptFrame(parsing: message.prompt)?.sender == .task(id: tasks[0].id, label: tasks[0].label))
    }

    @Test("Waiting on a task that isn't open reopens it first")
    func reopensClosedTasks() async throws {
        let runtime = FakeRuntime()
        let orchestrator = TaskOrchestrator(runtime: runtime)
        let parent = await runtime.openSession(agent: "claude", id: "p1")
        _ = try await orchestrator.startTask(agent: "codex", prompt: "one", title: "One", for: parent)
        let task = try #require(await runtime.tasks().first)
        await runtime.close(task.session)

        let result = try await orchestrator.waitForTask(task.id, timeout: .seconds(1), for: parent)

        #expect(await runtime.reopened == [task.id])
        #expect(result.structuredContent?["reply"]?.stringValue == "from before")
        #expect(result.text.contains("finished its turn"))
    }

    @Test("Until the runtime is ready, the tools say to try again")
    func notReady() async throws {
        let runtime = FakeRuntime()
        await runtime.setReady(false)
        let orchestrator = TaskOrchestrator(runtime: runtime)
        let parent = await runtime.openSession(agent: "claude")
        let result = try await tool("list_agents", orchestrator)(parent, arguments: [:])
        #expect(result.isError)
        #expect(result.text.contains("Try again shortly"))
    }

    @Test("A caller the runtime doesn't have can't start tasks")
    func unknownCaller() async throws {
        let orchestrator = TaskOrchestrator(runtime: FakeRuntime())
        let stranger = OrchestrationCaller(clientID: UUID(), agent: "claude", cwd: URL(filePath: "/"))
        let result = try await tool("start_task", orchestrator)(
            stranger, arguments: ["agent": "codex", "prompt": "hi"])
        #expect(result.isError)
        #expect(result.text.contains("doesn't have your task open"))
    }

    @Test("Skills switched off for the session are left out")
    func skills() async throws {
        let runtime = FakeRuntime()
        let orchestrator = TaskOrchestrator(runtime: runtime)
        let caller = await runtime.openSession(agent: "claude")
        let skills = [
            NativeSkill(id: "set-up-native", markdown: "# Set up\n\nHow."),
            NativeSkill(id: "build-a-native-plugin", markdown: "# Build\n\nHow."),
        ]
        #expect(await orchestrator.skills(skills, for: caller).map(\.id) == ["set-up-native"])
    }
}

@Suite("Task records and transcripts")
struct TaskRecordTests {
    @Test("Records the app saved before the package decode")
    func legacyRecords() throws {
        let json = Data(
            #"[{"id":"task-abc234","session":{"agent":{"rawValue":"codex"},"id":"s1"},"agentName":"Codex","title":"Review","parent":{"agent":{"rawValue":"claude"},"id":"p1"},"parentAgentName":"Claude Code"}]"#
                .utf8)
        let tasks = try JSONDecoder().decode([OrchestrationTask].self, from: json)
        #expect(tasks.first?.session == TaskSessionRef(agent: "codex", id: "s1"))
        #expect(tasks.first?.parent == TaskSessionRef(agent: "claude", id: "p1"))
        #expect(tasks.first?.cwd == nil)
        let again = try JSONDecoder().decode([OrchestrationTask].self, from: JSONEncoder().encode(tasks))
        #expect(again == tasks)
    }

    @Test("A card decodes as the subagent update agents send, and names its task")
    func cards() throws {
        let meta = TaskTranscript.CardMeta(taskID: "task-abc234", clientID: UUID(), agent: "codex")
        let card = TaskTranscript.card(
            session: SessionID("s1"), title: "Review", agentName: "Codex", state: .running, meta: meta)
        guard case .subagent(let update) = try decode(card) else {
            Issue.record("Not a subagent update")
            return
        }
        #expect(update.sessionId == SessionID("s1"))
        #expect(update.title == .set("Review"))
        #expect(update.description == .set("Codex"))
        #expect(update.canCancel == .set(true))
        #expect(update.state == .set(.running))
        #expect(TaskTranscript.CardMeta(update: card) == meta)

        let failed = TaskSnapshot(status: .failed, detail: "Codex stopped running.").workState
        let later = TaskTranscript.card(session: SessionID("s1"), state: failed, meta: meta)
        guard case .subagent(let change) = try decode(later) else {
            Issue.record("Not a subagent update")
            return
        }
        #expect(change.title == .unchanged)
        #expect(
            change.state == .set(.idle(stopReason: .error, error: RPCError(code: 0, message: "Codex stopped running.")))
        )
    }

    @Test("A message decodes as a session message")
    func messages() throws {
        guard
            case .sessionMessage(let message) = try decode(
                TaskTranscript.message("hello", from: SessionID("a"), to: SessionID("b")))
        else {
            Issue.record("Not a session message")
            return
        }
        #expect(message.senderSessionId == SessionID("a"))
        #expect(message.recipientSessionId == SessionID("b"))
        #expect(message.content == .set([.text("hello")]))
    }

    @Test("A session's state reads the same as a task wherever it runs")
    func snapshots() {
        var state = SessionState()
        state.appendNotice("Codex couldn't be reached.", isError: true)
        let failed = TaskSnapshot(
            phase: .idle, needsApproval: false, lastStopReason: .error, agentName: "Codex", state: state)
        #expect(failed.status == .failed)
        #expect(failed.detail == "Codex couldn't be reached.")
        #expect(
            TaskSnapshot(
                phase: .disconnected, needsApproval: false, lastStopReason: nil, agentName: "Codex", state: state
            )
            .detail == "Codex stopped running.")
        #expect(
            TaskSnapshot(phase: .running, needsApproval: true, lastStopReason: nil, agentName: "Codex", state: state)
                .status == .needsApproval)
        #expect(
            TaskSnapshot(phase: .loading, needsApproval: false, lastStopReason: nil, agentName: "Codex", state: state)
                .status == .running)
    }

    private func decode(_ json: JSONValue) throws -> SessionUpdate {
        try JSONDecoder().decode(SessionUpdate.self, from: JSONEncoder().encode(json))
    }
}
