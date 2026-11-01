import ACP
import Foundation
import NativeHostClient
import NativeHostProtocol
import Testing

@testable import NativeHost

/// A task's history through a real host and the fake agent: one per task, found again when the task
/// is reopened in a new host session, and gone with the task.
@Suite("Task history in the host", .serialized, .timeLimit(.minutes(1)))
struct HostHistoryTests {
    @Test("A session's history is found again after it closes and its agent session reopens")
    func reopened() async throws {
        let harness = try HostHarness()
        defer { harness.cleanup() }
        try harness.start()
        let recorder = try await harness.connect()
        let first = try await recorder.client.newSession(
            NewSessionParams(agentID: "fake", cwd: "/tmp", attach: true))
        let agentSession = try #require(first.agentSessionID)
        _ = try await recorder.client.prompt(PromptParams(sessionID: first.id, text: "hello"))
        try await recorder.wait("the turn") { await $0.turnsEnded(first.id) == ["end_turn"] }
        let summary = try await recorder.client.historySummary(of: first.id)
        #expect(summary.current == 1)
        #expect(summary.participants.map(\.agentID) == ["fake"])
        #expect(summary.participants.map(\.agentSessionID) == [agentSession])
        try await recorder.client.closeSession(first.id)

        let reopened = try await recorder.client.openSession(
            OpenSessionParams(agentID: "fake", agentSessionID: agentSession, cwd: "/tmp", attach: true))
        try await recorder.wait("the load") { await $0.summaries[reopened.id]?.phase == .idle }
        #expect(try await recorder.client.historySummary(of: reopened.id).id == summary.id)
        #expect(try await recorder.client.readHistory(ReadHistoryParams(sessionID: reopened.id)).isEmpty)
        await recorder.stop()
    }

    @Test("Deleting a task's agent session deletes its history")
    func deleted() async throws {
        let harness = try HostHarness()
        defer { harness.cleanup() }
        try harness.start()
        let recorder = try await harness.connect()
        let session = try await recorder.client.newSession(
            NewSessionParams(agentID: "fake", cwd: "/tmp", attach: true))
        let agentSession = try #require(session.agentSessionID)
        let summary = try await recorder.client.historySummary(of: session.id)
        try await recorder.client.deleteAgentSession(
            DeleteAgentSessionParams(agentID: "fake", agentSessionID: agentSession))
        await recorder.stop()
        let store = try HostStore(url: harness.location.databaseURL)
        #expect(try store.historyHead(summary.id) == nil)
        #expect(try store.historyParticipant(agentID: "fake", agentSessionID: agentSession) == nil)
    }
}
