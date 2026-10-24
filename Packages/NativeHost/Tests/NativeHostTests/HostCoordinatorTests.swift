#if canImport(Network) && canImport(CryptoKit)
import ACP
import Foundation
import NativeHostClient
import NativeHostProtocol
import NativeOrchestration
import Testing

@Suite("Coordinator tasks on the real host", .serialized, .timeLimit(.minutes(2)))
struct HostCoordinatorTests {
    private func identity(_ summary: HostSessionSummary) throws -> HostTaskIdentity {
        HostTaskIdentity(agentID: summary.agentID, agentSessionID: try #require(summary.agentSessionID))
    }

    @Test("Saved idle assignment history is readable after restarting the host")
    func readAfterRestart() async throws {
        let harness = try HostHarness()
        harness.agentEnvironment["FAKE_AGENT_READ_ONLY"] = "1"
        try harness.start()
        let first = try await harness.connect()
        let target = try await first.client.newSession(
            NewSessionParams(agentID: "fake", cwd: harness.root.path, attach: true))
        _ = try await first.client.prompt(PromptParams(sessionID: target.id, text: "Completed docs work"))
        try await first.wait("saved target") { await $0.turnsEnded(target.id) == ["end_turn"] }
        let owner = try await first.client.newCoordinator(
            NewCoordinatorParams(
                task: NewSessionParams(agentID: "fake", cwd: harness.root.path, attach: true),
                assignments: [try identity(target)]))
        _ = try await first.client.prompt(PromptParams(sessionID: owner.id, text: "Coordinate the docs"))
        try await first.wait("saved owner") { await $0.turnsEnded(owner.id) == ["end_turn"] }
        harness.kill()
        await first.stop()
        try harness.start()
        let restarted = try await harness.connect()
        for tool in ["get_task", "wait_for_task"] {
            let result = try await restarted.client.callTool(
                CallToolParams(
                    sessionID: owner.id, tool: tool,
                    arguments: .object(["task_id": .string("task-\(target.id)")])))
            #expect(!result.isError)
            #expect(result.text.contains("Completed docs work"))
        }
        await restarted.stop()
    }

    @Test("Closing an assigned task unsubscribes only the closing client")
    func unsubscribeOnClose() async throws {
        let harness = try HostHarness()
        harness.agentEnvironment["FAKE_AGENT_READ_ONLY"] = "1"
        try harness.start()
        let closing = try await harness.connect()
        let target = try await closing.client.newSession(
            NewSessionParams(agentID: "fake", cwd: harness.root.path, attach: true))
        _ = try await closing.client.newCoordinator(
            NewCoordinatorParams(
                task: NewSessionParams(agentID: "fake", cwd: harness.root.path), assignments: [try identity(target)]))
        let watching = try await harness.connect()
        try await watching.client.attach(target.id)
        try await closing.client.closeSession(target.id)
        let previous = await closing.events[target.id, default: []].count
        _ = try await watching.client.prompt(PromptParams(sessionID: target.id, text: "Only the remaining subscriber"))
        try await watching.wait("other client still follows") { await $0.turnsEnded(target.id) == ["end_turn"] }
        _ = try await closing.client.sessions()
        #expect(await closing.events[target.id, default: []].count == previous)
        #expect(await watching.agentText(target.id).contains("Only the remaining subscriber"))
        await closing.stop()
        await watching.stop()
    }

    @Test("Attached coordinators recover their transcript after a dropped connection", arguments: [false, true])
    func reconnect(suppliesID: Bool) async throws {
        let harness = try HostHarness()
        harness.agentEnvironment["FAKE_AGENT_READ_ONLY"] = "1"
        try harness.start()
        let transport = CuttableTransport(location: harness.location)
        let recorder = try await harness.connect(transport: transport)
        let owner = try await recorder.client.newCoordinator(
            NewCoordinatorParams(
                task: NewSessionParams(
                    sessionID: suppliesID ? HostSessionID() : nil, agentID: "fake", cwd: harness.root.path,
                    attach: true), assignments: []))
        _ = try await recorder.client.prompt(PromptParams(sessionID: owner.id, text: "slow 8"))
        try await recorder.wait("the coordinator turn") { await $0.agentText(owner.id).contains("tick 2") }
        transport.cut()
        try await recorder.wait("the reattached coordinator", timeout: .seconds(8)) {
            await $0.turnsEnded(owner.id) == ["end_turn"]
        }
        #expect(await recorder.agentText(owner.id) == (1...8).map { "tick \($0)\n" }.joined())
        await recorder.stop()
    }

    @Test("Closing coordinated tasks keeps them discoverable and resumes them for messages", arguments: [false, true])
    func closedTasks(hasHistory: Bool) async throws {
        let harness = try HostHarness()
        harness.agentEnvironment["FAKE_AGENT_READ_ONLY"] = "1"
        try harness.start()
        let recorder = try await harness.connect()
        let client = recorder.client
        let target = try await client.newSession(
            NewSessionParams(agentID: "fake", cwd: harness.root.path, attach: true))
        if hasHistory {
            _ = try await client.prompt(PromptParams(sessionID: target.id, text: "Existing docs work"))
            try await recorder.wait("saved target") { await $0.turnsEnded(target.id) == ["end_turn"] }
        }
        let assigned = try identity(target)
        let assignedID = "task-\(target.id)"
        let owner = try await client.newCoordinator(
            NewCoordinatorParams(
                task: NewSessionParams(agentID: "fake", cwd: harness.root.path), assignments: [assigned]))
        try await client.closeSession(target.id, closeInAgent: true)
        try await client.closeSession(owner.id, closeInAgent: true)
        let list = try await client.callTool(
            CallToolParams(sessionID: owner.id, tool: "list_tasks", arguments: .object([:])))
        #expect(list.text.contains(assignedID))
        let summary = try await client.callTool(
            CallToolParams(
                sessionID: owner.id, tool: "get_task", arguments: .object(["task_id": .string(assignedID)])))
        #expect(!summary.isError)
        if hasHistory { #expect(summary.text.contains("Existing docs work")) }
        let message = try await client.callTool(
            CallToolParams(
                sessionID: owner.id, tool: "send_message",
                arguments: .object(["to": .string(assignedID), "message": .string("Align after closing")])))
        #expect(!message.isError)
        let waited = try await client.callTool(
            CallToolParams(
                sessionID: owner.id, tool: "wait_for_task",
                arguments: .object(["task_id": .string(assignedID)])))
        #expect(!waited.isError)
        try await client.attach(target.id)
        try await recorder.wait("message after closing") {
            await $0.agentText(target.id).contains("Align after closing")
        }
        var record = try #require(try await client.coordinators().first)
        record.assignments = []
        try await client.setCoordinator(record)
        try await client.closeSession(target.id, closeInAgent: true)
        #expect(try await !client.sessions().contains { $0.id == target.id })
        await recorder.stop()
    }

    @Test("Unsupported read-only fails without publishing a coordinator")
    func unsupported() async throws {
        let harness = try HostHarness()
        try harness.start()
        let recorder = try await harness.connect()
        await #expect(throws: (any Error).self) {
            try await recorder.client.newCoordinator(
                NewCoordinatorParams(
                    task: NewSessionParams(agentID: "fake", cwd: harness.root.path), assignments: []))
        }
        #expect(try await recorder.client.coordinators().isEmpty)
        #expect(try await recorder.client.sessions().isEmpty)
        #expect(harness.received.contains { $0.hasPrefix("delete\t") })
        await recorder.stop()
    }

    @Test("Deleting a coordinator releases its tasks without deleting or stopping them")
    func deletion() async throws {
        let harness = try HostHarness()
        harness.agentEnvironment["FAKE_AGENT_READ_ONLY"] = "1"
        try harness.start()
        let recorder = try await harness.connect()
        let client = recorder.client
        let target = try await client.newSession(NewSessionParams(agentID: "fake", cwd: harness.root.path))
        _ = try await client.prompt(PromptParams(sessionID: target.id, text: "slow 30"))
        let assigned = try identity(target)
        let params = NewCoordinatorParams(
            task: NewSessionParams(agentID: "fake", cwd: harness.root.path), assignments: [assigned])
        let owner = try await client.newCoordinator(params)
        try await client.deleteAgentSession(
            DeleteAgentSessionParams(agentID: "fake", agentSessionID: try #require(owner.agentSessionID)))
        #expect(try await client.sessions().contains { $0.id == target.id && $0.isWorking })
        let replacement = try await client.newCoordinator(params)
        #expect(replacement.id != owner.id)
        await recorder.stop()
    }

    @Test("Read-only creation, scoped messages, exclusive ownership, revocation and host restart")
    func lifecycle() async throws {
        let harness = try HostHarness()
        harness.agentEnvironment["FAKE_AGENT_READ_ONLY"] = "1"
        try harness.start()
        let recorder = try await harness.connect()
        let client = recorder.client
        let target = try await client.newSession(
            NewSessionParams(agentID: "fake", cwd: harness.root.path, attach: true))
        let unrelated = try await client.newSession(NewSessionParams(agentID: "fake", cwd: harness.root.path))
        let assigned = try identity(target)
        let assignedID = "task-\(target.id)"
        let strangerID = "task-\(unrelated.id)"
        let params = NewCoordinatorParams(
            task: NewSessionParams(sessionID: HostSessionID(), agentID: "fake", cwd: harness.root.path, attach: true),
            assignments: [assigned])
        let coordinator = try await client.newCoordinator(params)
        #expect(try await client.newCoordinator(params).id == coordinator.id)
        #expect(coordinator.cwd == harness.root.path)
        #expect(coordinator.parentID == nil)
        _ = try await client.prompt(PromptParams(sessionID: coordinator.id, text: "config?"))
        try await recorder.wait("coordinator config") { await $0.agentText(coordinator.id).contains("mode=read-only") }
        _ = try await client.prompt(PromptParams(sessionID: coordinator.id, text: "tool list_tasks {}"))
        try await recorder.wait("scoped MCP listing from the agent") {
            await $0.agentText(coordinator.id).contains(assignedID)
        }
        let listed = try await client.callTool(
            CallToolParams(sessionID: coordinator.id, tool: "list_tasks", arguments: .object([:])))
        #expect(listed.text.contains(assignedID))
        #expect(!listed.text.contains(strangerID))
        for name in ["get_task", "cancel_task"] {
            let result = try await client.callTool(
                CallToolParams(
                    sessionID: coordinator.id, tool: name, arguments: .object(["task_id": .string(strangerID)])))
            #expect(result.isError)
        }
        let started = try await client.callTool(
            CallToolParams(
                sessionID: coordinator.id, tool: "start_task",
                arguments: .object(["agent": .string("fake"), "prompt": .string("denied")])))
        #expect(started.isError)
        await #expect(throws: (any Error).self) {
            try await client.newCoordinator(
                NewCoordinatorParams(
                    task: NewSessionParams(agentID: "fake", cwd: harness.root.path), assignments: [assigned]))
        }
        var record = try #require(try await client.coordinators().first)
        let original = record
        record.assignments = [record.task]
        await #expect(throws: (any Error).self) { try await client.setCoordinator(record) }
        record = original
        let message = try await client.callTool(
            CallToolParams(
                sessionID: coordinator.id, tool: "send_message",
                arguments: .object(["to": .string(assignedID), "message": .string("Align the docs")])))
        #expect(!message.isError)
        try await recorder.wait("coordinator message in target") { recorder in
            await recorder.mirror(target.id).state.items.contains { item in
                guard case .sessionMessage(let message) = item else { return false }
                return TaskPromptFrame(parsing: message.text)?.body == "Align the docs"
            }
        }
        record.assignments = []
        try await client.setCoordinator(record)
        let revoked = try await client.callTool(
            CallToolParams(
                sessionID: coordinator.id, tool: "send_message",
                arguments: .object(["to": .string(assignedID), "message": .string("revoked")])))
        #expect(revoked.isError)
        harness.kill()
        await recorder.stop()
        try harness.start()
        let reopened = try await harness.connect()
        #expect(try await reopened.client.coordinators() == [record])
        let after = try await reopened.client.callTool(
            CallToolParams(
                sessionID: coordinator.id, tool: "start_task",
                arguments: .object(["agent": .string("fake"), "prompt": .string("still denied")])))
        #expect(after.isError)
        await reopened.stop()
    }
}
#endif
