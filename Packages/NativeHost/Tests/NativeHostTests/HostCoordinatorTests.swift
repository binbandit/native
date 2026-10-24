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
        let stranger = try identity(unrelated)
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
            await $0.agentText(coordinator.id).contains(assigned.toolID)
        }
        let listed = try await client.callTool(
            CallToolParams(sessionID: coordinator.id, tool: "list_tasks", arguments: .object([:])))
        #expect(listed.text.contains(assigned.toolID))
        #expect(!listed.text.contains(stranger.toolID))
        for name in ["get_task", "cancel_task"] {
            let result = try await client.callTool(
                CallToolParams(
                    sessionID: coordinator.id, tool: name, arguments: .object(["task_id": .string(stranger.toolID)])))
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
                arguments: .object(["to": .string(assigned.toolID), "message": .string("Align the docs")])))
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
                arguments: .object(["to": .string(assigned.toolID), "message": .string("revoked")])))
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
