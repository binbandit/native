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
        // Reopening reads the same history; its replay is not brought in again.
        #expect(try await recorder.client.readHistory(ReadHistoryParams(sessionID: reopened.id)).count == 3)
        await recorder.stop()
    }

    @Test("Each turn records its message, the agent's reply and how it ended, numbered on")
    func recordsTurns() async throws {
        let harness = try HostHarness()
        defer { harness.cleanup() }
        try harness.start()
        let recorder = try await harness.connect()
        let session = try await recorder.client.newSession(
            NewSessionParams(agentID: "fake", cwd: "/tmp", attach: true))
        let first = UUID()
        _ = try await recorder.client.prompt(PromptParams(sessionID: session.id, requestID: first, text: "hello"))
        try await recorder.wait("the first turn") { await $0.turnsEnded(session.id) == ["end_turn"] }
        // A repeat of the same request is answered from the store and records nothing again.
        _ = try await recorder.client.prompt(PromptParams(sessionID: session.id, requestID: first, text: "hello"))
        _ = try await recorder.client.prompt(PromptParams(sessionID: session.id, text: "again"))
        try await recorder.wait("the second turn") { await $0.turnsEnded(session.id).count == 2 }

        let items = try await recorder.client.readHistory(ReadHistoryParams(sessionID: session.id))
        #expect(items.map(\.seq) == Array(1...6))
        #expect(
            items.map(\.body) == [
                .user(.init(text: "hello", origin: "user")), .agent("echo: hello"), .turnEnded(stopReason: "end_turn"),
                .user(.init(text: "again", origin: "user")), .agent("echo: again"), .turnEnded(stopReason: "end_turn"),
            ])
        #expect(items.allSatisfy { $0.source == 1 && $0.at != nil })
        #expect(items.prefix(3).allSatisfy { $0.turn == first })
        #expect(try await recorder.client.historySummary(of: session.id).head == 6)
        await recorder.stop()
    }

    @Test("A conversation from before its task had a history brings its replay in once")
    func importsReplay() async throws {
        let harness = try HostHarness()
        defer { harness.cleanup() }
        try harness.start()
        let recorder = try await harness.connect()
        let session = try await recorder.client.newSession(
            NewSessionParams(agentID: "fake", cwd: "/tmp", attach: true))
        _ = try await recorder.client.prompt(PromptParams(sessionID: session.id, text: "hello"))
        try await recorder.wait("the turn") { await $0.turnsEnded(session.id) == ["end_turn"] }
        await recorder.stop()
        harness.kill()
        // As a store from before version 14 would be: the session, and no history.
        try HostStore(url: harness.location.databaseURL).database.execute("DELETE FROM histories")

        try harness.start()
        let second = try await harness.connect()
        try await second.client.attach(session.id)
        try await second.wait("the replay") { await $0.agentText(session.id) == "echo: hello" }
        try await second.wait("the load") { await $0.summaries[session.id]?.phase == .idle }
        let items = try await second.client.readHistory(ReadHistoryParams(sessionID: session.id))
        #expect(items.map(\.body) == [.user(.init(text: "hello", origin: "user")), .agent("echo: hello")])
        #expect(items.allSatisfy { $0.turn == nil && $0.at == nil })
        await second.stop()
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
