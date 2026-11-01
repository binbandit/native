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

    @Test("A message sent to a conversation from before the history waits for its replay to be imported")
    func importsBeforeFirstMessage() async throws {
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
        try HostStore(url: harness.location.databaseURL).database.execute("DELETE FROM histories")

        try harness.start()
        let second = try await harness.connect()
        // Sent before anything attached: the session loads for it, and its old turn comes first.
        _ = try await second.client.prompt(PromptParams(sessionID: session.id, text: "again"))
        try await second.wait("both turns in the history") {
            (try? await $0.client.readHistory(ReadHistoryParams(sessionID: session.id)))?.count == 5
        }
        let items = try await second.client.readHistory(ReadHistoryParams(sessionID: session.id))
        #expect(
            items.map(\.body) == [
                .user(.init(text: "hello", origin: "user")), .agent("echo: hello"),
                .user(.init(text: "again", origin: "user")), .agent("echo: again"), .turnEnded(stopReason: "end_turn"),
            ])
        #expect(items.map { $0.turn == nil } == [true, true, false, false, false])
        await second.stop()
    }

    @Test("A message stopped while its first load after an upgrade hangs is still recorded, once")
    func stoppedFirstLoad() async throws {
        let harness = try HostHarness()
        defer { harness.cleanup() }
        harness.agentEnvironment["FAKE_AGENT_NO_RESUME"] = "1"
        harness.agentEnvironment["FAKE_AGENT_LOAD_HANG_ONCE"] = "1"
        try harness.start()
        let recorder = try await harness.connect()
        let session = try await recorder.client.newSession(
            NewSessionParams(agentID: "fake", cwd: "/tmp", attach: true))
        _ = try await recorder.client.prompt(PromptParams(sessionID: session.id, text: "hello"))
        try await recorder.wait("the turn") { await $0.turnsEnded(session.id) == ["end_turn"] }
        await recorder.stop()
        harness.kill()
        try HostStore(url: harness.location.databaseURL).database.execute("DELETE FROM histories")

        try harness.start()
        let second = try await harness.connect()
        _ = try await second.client.prompt(PromptParams(sessionID: session.id, text: "stopped"))
        try await second.wait("the hung load") { _ in
            ((try? String(contentsOf: harness.agentStore.appending(path: "loads.log"), encoding: .utf8)) ?? "")
                .contains("waiting")
        }
        try await second.client.cancel(session.id)
        try await second.wait("the stop") {
            (try? await $0.client.readHistory(ReadHistoryParams(sessionID: session.id)))?.count == 2
        }
        // The load never finished, so the history starts with the message rather than losing it.
        #expect(
            try await second.client.readHistory(ReadHistoryParams(sessionID: session.id)).map(\.body) == [
                .user(.init(text: "stopped", origin: "user")), .turnEnded(stopReason: "cancelled"),
            ])
        await second.stop()
    }

    @Test("A participant's model follows the model its messages go to")
    func modelFollows() async throws {
        let harness = try HostHarness()
        defer { harness.cleanup() }
        try harness.start()
        let recorder = try await harness.connect()
        let session = try await recorder.client.newSession(NewSessionParams(agentID: "fake", cwd: "/tmp", attach: true))
        _ = try await recorder.client.prompt(PromptParams(sessionID: session.id, text: "one"))
        try await recorder.wait("the first turn") { await $0.turnsEnded(session.id).count == 1 }
        #expect(try await recorder.client.historySummary(of: session.id).participants.map(\.model) == ["alpha"])
        try await recorder.client.setConfigOption(
            SetConfigOptionParams(sessionID: session.id, configID: "model", value: "beta"))
        _ = try await recorder.client.prompt(PromptParams(sessionID: session.id, text: "two"))
        try await recorder.wait("the second turn") { await $0.turnsEnded(session.id).count == 2 }
        #expect(try await recorder.client.historySummary(of: session.id).participants.map(\.model) == ["beta"])
        await recorder.stop()
    }

    /// Two sessions on the fake agent standing in for two agents of one task.
    private func twoSessions(_ recorder: Recorder) async throws -> (HostSessionSummary, HostSessionID) {
        let first = try await recorder.client.newSession(NewSessionParams(agentID: "fake", cwd: "/tmp", attach: true))
        _ = try await recorder.client.prompt(PromptParams(sessionID: first.id, text: "one"))
        try await recorder.wait("the first turn") { await $0.turnsEnded(first.id) == ["end_turn"] }
        let second = try await recorder.client.newSession(NewSessionParams(agentID: "fake", cwd: "/tmp", attach: true))
        return (first, second.id)
    }

    /// The second session continues the first, as a committed change of agent does.
    private func join(
        _ recorder: Recorder, _ second: HostSessionID, after first: HostSessionSummary,
        conveyed: [ClosedRange<Int>] = []
    ) async throws -> TaskHistorySummary {
        try await recorder.client.joinHistory(
            JoinHistoryParams(
                sessionID: second, sourceAgentID: first.agentID,
                sourceAgentSessionID: try #require(first.agentSessionID), conveyed: conveyed))
    }

    @Test("A joined session sees what its handoff conveyed once its message is answered, and nothing more")
    func joinedWatermark() async throws {
        let harness = try HostHarness()
        defer { harness.cleanup() }
        try harness.start()
        let recorder = try await harness.connect()
        let (first, second) = try await twoSessions(recorder)
        // The handoff quoted the reply (item 2) but not the message before it.
        let joined = try await join(recorder, second, after: first, conveyed: [2...2, 7...9])
        #expect(joined.current == 2)
        #expect(joined.participants.map(\.seen) == [3, 0])
        #expect(joined.transfers.map(\.state) == [.prepared])
        #expect(joined.transfers.map(\.conveyed) == [[2...2]])
        // A client retrying the join after a lost reply records its handoff once.
        let again = try await join(recorder, second, after: first, conveyed: [2...2])
        #expect(again.transfers.count == 1)

        _ = try await recorder.client.prompt(PromptParams(sessionID: second, text: "two"))
        try await recorder.wait("the second turn") { await $0.turnsEnded(second).count == 1 }
        let after = try await recorder.client.historySummary(of: second)
        #expect(after.head == 6)
        #expect(after.transfers.map(\.state) == [.delivered])
        // Item 1 was never conveyed, so the second session's watermark can't pass it.
        #expect(after.participants.map(\.seen) == [3, 0])
        #expect(try await recorder.client.missingHistory(of: second).items.map(\.seq) == [1, 3])
        // The first session missed everything the second did.
        let missed = try await recorder.client.missingHistory(of: first.id)
        #expect(missed.seen == 3)
        #expect(
            missed.items.map(\.body) == [
                .user(.init(text: "two", origin: "user")), .agent("echo: two"), .turnEnded(stopReason: "end_turn"),
            ])
        await recorder.stop()
    }

    @Test("A handoff that conveyed everything carries the watermark to the head, after its source closed")
    func fullHandoff() async throws {
        let harness = try HostHarness()
        defer { harness.cleanup() }
        try harness.start()
        let recorder = try await harness.connect()
        let (first, second) = try await twoSessions(recorder)
        // The conversation it continues from is found through its agent session once its own closed.
        try await recorder.client.closeSession(first.id)
        _ = try await join(recorder, second, after: first, conveyed: [1...3])
        // Before its message is answered, nothing it was given counts.
        #expect(try await recorder.client.missingHistory(of: second).items.count == 3)
        _ = try await recorder.client.prompt(PromptParams(sessionID: second, text: "two"))
        try await recorder.wait("the second turn") { await $0.turnsEnded(second).count == 1 }
        #expect(try await recorder.client.historySummary(of: second).participants.map(\.seen) == [3, 6])
        #expect(try await recorder.client.missingHistory(of: second).items.isEmpty)
        await recorder.stop()
    }

    @Test("A handoff whose message was stopped before the agent answered isn't counted as seen")
    func stoppedBeforeAnswer() async throws {
        let harness = try HostHarness()
        defer { harness.cleanup() }
        try harness.start()
        let recorder = try await harness.connect()
        let (first, second) = try await twoSessions(recorder)
        _ = try await join(recorder, second, after: first, conveyed: [1...3])
        _ = try await recorder.client.prompt(PromptParams(sessionID: second, text: "silent-until-stopped"))
        try await recorder.wait("the agent to get the message") { _ in
            harness.received.contains("prompt\tsilent-until-stopped")
        }
        try await recorder.client.cancel(second)
        try await recorder.wait("the stop") { await $0.turnsEnded(second) == ["cancelled"] }
        let summary = try await recorder.client.historySummary(of: second)
        #expect(summary.transfers.map(\.state) == [.sent])
        #expect(summary.participants.map(\.seen) == [3, 0])
        #expect(try await recorder.client.missingHistory(of: second).items.map(\.seq) == [1, 2, 3])
        await recorder.stop()
    }

    @Test("A change of agent undone before its first message leaves the task's history as it was")
    func undoneJoin() async throws {
        let harness = try HostHarness()
        defer { harness.cleanup() }
        try harness.start()
        let recorder = try await harness.connect()
        let (first, second) = try await twoSessions(recorder)
        // A handoff the client can't itemize is still recorded, crediting nothing.
        let joined = try await join(recorder, second, after: first)
        #expect(joined.transfers.map(\.conveyed) == [[]])
        try await recorder.client.closeSession(second, closeInAgent: true)
        let summary = try await recorder.client.historySummary(of: first.id)
        #expect(summary.participants.count == 1)
        #expect(summary.transfers.isEmpty)
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
