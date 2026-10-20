// Native's tools need the MCP server, which needs Network and CryptoKit (`HostTasks.canServe`).
#if canImport(Network) && canImport(CryptoKit)
import ACP
import Foundation
import NativeHostClient
import NativeHostProtocol
import NativeOrchestration
import Testing

/// Native's tools served by the host: a real `native-host` process whose fake agents call them over
/// MCP, as Claude Code and Codex do, while clients come and go and the host is killed.
@Suite("Native's tools in the host", .serialized, .timeLimit(.minutes(2)))
struct HostTasksTests {
    private func parent(_ recorder: Recorder, harness: HostHarness) async throws -> HostSessionID {
        let summary = try await recorder.client.newSession(
            NewSessionParams(agentID: "fake", cwd: harness.root.path(percentEncoded: false), attach: true))
        return summary.id
    }

    /// The task the parent started, once the host has it.
    private func task(of parent: HostSessionID, _ recorder: Recorder) async throws -> HostTask {
        try await recorder.wait("the task to start") { recorder in
            (try? await recorder.client.tasks().contains { $0.parentSessionID == parent }) == true
        }
        return try #require(try await recorder.client.tasks().first { $0.parentSessionID == parent })
    }

    @Test("A delegated task runs as a session of the host and its reply goes back to the parent")
    func delegates() async throws {
        let harness = try HostHarness()
        try harness.start()
        let recorder = try await harness.connect()
        let parent = try await parent(recorder, harness: harness)
        _ = try await recorder.client.prompt(PromptParams(sessionID: parent, text: "delegate look around"))

        try await recorder.wait("the parent to end its turn") { await $0.turnsEnded(parent) == ["end_turn"] }
        #expect(await recorder.agentText(parent) == "delegated: echo: look around")

        let task = try await task(of: parent, recorder)
        let parentSummary = try #require(await recorder.summaries[parent])
        #expect(task.title == "Delegated")
        #expect(task.agentID == "fake")
        #expect(task.parentAgentSessionID == parentSummary.agentSessionID)
        let child = try #require(task.sessionID)
        let summary = try #require(await recorder.summaries[child])
        #expect(summary.origin == .task)
        #expect(summary.parentID == parent)
        #expect(summary.title == "Delegated")

        // The parent's transcript shows the task as a card that names it, and follows its state.
        let cards = await recorder.mirror(parent).state.subagents
        #expect(cards.map(\.title) == ["Delegated"])
        #expect(cards.first?.workState == .idle(stopReason: .endTurn, error: nil))
        let meta = await recorder.payloads(parent).compactMap { payload -> TaskTranscript.CardMeta? in
            if case .update(let update) = payload { TaskTranscript.CardMeta(update: update) } else { nil }
        }
        #expect(meta.first?.taskID == task.id)
        #expect(meta.first?.clientID == child.rawValue)

        // The task's own transcript has the parent's message, not the header it was prompted with.
        try await recorder.client.attach(child)
        try await recorder.wait("the task's log") { await !$0.payloads(child).isEmpty }
        let messages = await recorder.mirror(child).state.items.compactMap { item -> String? in
            if case .sessionMessage(let message) = item { message.text } else { nil }
        }
        #expect(messages == ["look around"])
        await recorder.stop()
    }

    @Test("A task and its parent finish with no client attached")
    func noClient() async throws {
        let harness = try HostHarness()
        try harness.start()
        let first = try await harness.connect()
        let parent = try await parent(first, harness: harness)
        _ = try await first.client.prompt(PromptParams(sessionID: parent, text: "delegate slow 4"))
        _ = try await task(of: parent, first)
        await first.stop()

        try await Task.sleep(for: .seconds(3))
        let second = try await harness.connect()
        try await second.client.attach(parent)
        try await second.wait("the parent's turn to end") { await $0.turnsEnded(parent) == ["end_turn"] }
        #expect(await second.agentText(parent).hasPrefix("delegated: tick 1"))
        await second.stop()
    }

    @Test("Killing the host while a parent waits on its task: both come back and finish")
    func hostKilled() async throws {
        let harness = try HostHarness()
        try harness.start()
        let first = try await harness.connect()
        let parent = try await parent(first, harness: harness)
        _ = try await first.client.prompt(PromptParams(sessionID: parent, text: "delegate slow 30"))
        let task = try await task(of: parent, first)
        let child = try #require(task.sessionID)
        try await first.client.attach(child)
        try await first.wait("the task to get going") { await $0.agentText(child).contains("tick 2") }
        let port = try String(contentsOf: harness.home.appending(path: "MCP/port"), encoding: .utf8)
        harness.kill()
        await first.stop()

        try harness.start()
        let second = try await harness.connect()
        try await second.client.attach(parent)
        try await second.client.attach(child)
        try await second.wait("the task and its parent to finish", timeout: .seconds(40)) {
            let parentEnded = await $0.turnsEnded(parent).last == "end_turn"
            let childEnded = await $0.turnsEnded(child).last == "end_turn"
            return parentEnded && childEnded
        }
        // The task was told it was interrupted, and the parent went back to waiting for it.
        #expect(await second.recoveries(child).map(\.action) == [.resumed])
        #expect(await second.recoveries(parent).map(\.action) == [.resumed])
        #expect(await second.agentText(parent).hasSuffix("delegated: resumed"))
        #expect(try await second.client.tasks().map(\.id) == [task.id])
        // The tools kept their address, so URLs handed out before the restart still reach them.
        #expect(try String(contentsOf: harness.home.appending(path: "MCP/port"), encoding: .utf8) == port)
        // The parent's card is back after its reload, showing how the task ended.
        #expect(await second.mirror(parent).state.subagents.map(\.title) == ["Delegated"])
        await second.stop()
    }

    @Test("A token the host didn't sign gets nothing")
    func forgedTokens() async throws {
        let harness = try HostHarness()
        try harness.start()
        let recorder = try await harness.connect()
        let parent = try await parent(recorder, harness: harness)
        let port = try String(contentsOf: harness.home.appending(path: "MCP/port"), encoding: .utf8)
        let id = parent.rawValue.uuidString.lowercased()
        // The bare session id, a MAC of the right length from another secret, and a malformed one.
        for token in [id, "\(id).\(String(repeating: "ab", count: 32))", "\(id).zz"] {
            var request = URLRequest(url: try #require(URL(string: "http://127.0.0.1:\(port)/mcp/\(token)")))
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue("2025-11-25", forHTTPHeaderField: "MCP-Protocol-Version")
            request.httpBody = Data(
                #"{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"list_agents","arguments":{}}}"#.utf8)
            let (_, response) = try await URLSession.shared.data(for: request)
            #expect((response as? HTTPURLResponse)?.statusCode == 404)
        }
        // While the session's own URL works.
        _ = try await recorder.client.prompt(PromptParams(sessionID: parent, text: "tool list_agents {}"))
        try await recorder.wait("the call") { await $0.turnsEnded(parent) == ["end_turn"] }
        #expect(await recorder.agentText(parent).contains("- fake: Fake Agent (the agent you are)"))
        await recorder.stop()
    }

    @Test("Tools only the Mac app answers go to it, and say why they can't run while it's closed")
    func appTools() async throws {
        let harness = try HostHarness()
        try harness.start()
        let app = try await harness.connect()
        let echo = AppToolDefinition(
            name: "app_echo", title: "Echo", description: "Answered by the app.",
            inputSchema: .object(["type": .string("object")]), outputSchema: nil,
            annotations: .object(["readOnlyHint": .bool(true)]))
        let client = app.client
        await client.addAppToolHandler { call in
            Task {
                let text = call.kind == .call ? "app: \(call.arguments["text"]?.stringValue ?? "")" : ""
                try? await client.answerAppTool(AppToolResult(callID: call.callID, result: ToolResult(text: text)))
            }
        }
        try await client.configureTasks(ConfigureTasksParams(servesTools: true, appTools: [echo]))
        let parent = try await parent(app, harness: harness)
        _ = try await client.prompt(PromptParams(sessionID: parent, text: #"tool app_echo {"text":"hi"}"#))
        try await app.wait("the call") { await $0.turnsEnded(parent) == ["end_turn"] }
        #expect(await app.agentText(parent) == "tool: app: hi")

        // The app's run_script calls the host's own tools back for the session.
        let listed = try await client.callTool(
            CallToolParams(sessionID: parent, tool: "list_agents", arguments: .object([:])))
        #expect(listed.text.contains("- fake: Fake Agent (the agent you are)"))

        // With the app gone, the tool is still there, and says what to do instead.
        await app.stop()
        let other = try await harness.connect()
        try await other.client.attach(parent)
        _ = try await other.client.prompt(PromptParams(sessionID: parent, text: #"tool app_echo {"text":"again"}"#))
        try await other.wait("the refused call") { await $0.turnsEnded(parent).count == 2 }
        #expect(await other.agentText(parent).contains("isn't open right now"))
        await other.stop()
    }

    @Test("Every session gets the host's tools, unless the Mac app serves them itself")
    func servingSwitch() async throws {
        let harness = try HostHarness()
        try harness.start()
        let recorder = try await harness.connect()
        let appServer = JSONValue.object([
            "name": .string("native"), "command": .string("/usr/bin/true"), "args": .array([]), "env": .array([]),
        ])
        let cwd = harness.root.path(percentEncoded: false)
        _ = try await recorder.client.newSession(NewSessionParams(agentID: "fake", cwd: cwd, mcpServers: [appServer]))
        try await recorder.client.configureTasks(ConfigureTasksParams(servesTools: false))
        _ = try await recorder.client.newSession(NewSessionParams(agentID: "fake", cwd: cwd, mcpServers: [appServer]))
        let news = try String(contentsOf: harness.agentStore.appending(path: "news.log"), encoding: .utf8)
        #expect(news == "native \nnative /usr/bin/true\n")
        await recorder.stop()
    }
}
#endif
